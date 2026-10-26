require "net/http"
require "json"

module Providers
  # SerpApi Google organic search over a small Net::HTTP client.
  #
  # Why not the official gem: its persistent mode (the default) does not apply the
  # timeout option to requests, and it raises on the top-level "error" key even
  # though SerpApi reports an empty result set that way. Behavior below follows
  # https://serpapi.com/search-api and https://serpapi.com/api-status-and-error-codes.
  #
  # The endpoint is a constant: nothing user-supplied is ever used as a fetch target.
  class SerpApiSearchProvider
    ENDPOINT = URI("https://serpapi.com/search").freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15
    MAX_BODY_BYTES = 5 * 1024 * 1024
    UNCONFIGURED_KEYS = [ "", "replace_me" ].freeze

    # Documented: empty results come back as HTTP 200 with this top-level "error".
    NO_RESULTS_MESSAGE = /hasn't returned any results/i
    # Documented: 429 is used both for the hourly limit and for exhausted searches.
    OUT_OF_SEARCHES_MESSAGE = /run out of searches/i

    URL_MAX_LENGTH = SearchResult::URL_MAX_LENGTH
    DISPLAYED_LINK_MAX_LENGTH = 300

    def self.from_env
      new(api_key: ENV["SERPAPI_API_KEY"])
    end

    def initialize(api_key:, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, no_cache: false)
      @api_key = api_key.to_s.strip
      raise SearchProvider::NotConfigured, "SERPAPI_API_KEY is not configured" if UNCONFIGURED_KEYS.include?(@api_key)

      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @no_cache = no_cache
    end

    def search(request)
      response = perform(request)
      parse(response.code.to_i, response.body)
    end

    private

    def perform(request)
      uri = ENDPOINT.dup
      uri.query = URI.encode_www_form(query_params(request))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.write_timeout = @read_timeout
      http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json"))
    rescue Timeout::Error # includes Net::OpenTimeout and Net::ReadTimeout
      raise SearchProvider::Error.new("SerpApi request timed out", category: :timeout)
    rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError
      raise SearchProvider::Error.new("SerpApi connection failed", category: :network)
    end

    # Only documented parameters: engine, q, gl, hl, location, output, no_cache, api_key.
    def query_params(request)
      {
        engine: request.engine,
        q: request.query,
        gl: request.country,
        hl: request.language,
        location: request.location,
        output: "json",
        no_cache: (@no_cache ? "true" : nil),
        api_key: @api_key
      }.compact
    end

    def parse(status, raw_body)
      body = decode(raw_body)
      raise http_error(status, body) unless status == 200
      raise SearchProvider::Error.new("SerpApi returned malformed JSON", category: :schema, http_status: status) unless body.is_a?(Hash)

      check_embedded_error(body, status)
      build_response(body)
    end

    def decode(raw_body)
      text = raw_body.to_s
      if text.bytesize > MAX_BODY_BYTES
        raise SearchProvider::Error.new("SerpApi response is too large", category: :schema)
      end

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def http_error(status, body)
      message = error_message(body)
      category =
        case status
        when 400, 404 then :invalid_request
        when 401, 403 then :auth
        when 408 then :timeout
        when 429 then message.match?(OUT_OF_SEARCHES_MESSAGE) ? :quota : :rate_limit
        when 500..599 then :upstream
        else :unknown
        end

      detail = message.empty? ? "" : ": #{message}"
      SearchProvider::Error.new("SerpApi returned HTTP #{status}#{detail}", category: category, http_status: status)
    end

    # SerpApi can report failures inside an HTTP 200 body. An empty result set is
    # reported the same way but is a success, so it is handled in build_response.
    def check_embedded_error(body, status)
      message = error_message(body)
      return if message.empty? || message.match?(NO_RESULTS_MESSAGE)

      category =
        if message.match?(/api key/i) then :auth
        elsif message.match?(OUT_OF_SEARCHES_MESSAGE) then :quota
        elsif message.match?(/missing|invalid|unsupported|parameter/i) then :invalid_request
        else :unknown
        end
      raise SearchProvider::Error.new("SerpApi error: #{message}", category: category, http_status: status)
    end

    def build_response(body)
      metadata = body["search_metadata"]
      search_id = metadata["id"].to_s.presence if metadata.is_a?(Hash)

      if metadata.is_a?(Hash) && metadata["status"] == "Error"
        raise SearchProvider::Error.new("SerpApi search failed upstream", category: :upstream, http_status: 200)
      end

      unless metadata.is_a?(Hash) || body.key?("search_information") || body.key?("organic_results")
        raise SearchProvider::Error.new("SerpApi response has an unexpected shape", category: :schema, http_status: 200)
      end

      # Documented empty-result signal, or a successful response without organic results.
      return empty_response(search_id) if error_message(body).match?(NO_RESULTS_MESSAGE)

      organic = body["organic_results"]
      return empty_response(search_id) if organic.nil?

      unless organic.is_a?(Array)
        raise SearchProvider::Error.new("organic_results is not an array", category: :schema, http_status: 200)
      end
      return empty_response(search_id) if organic.empty?

      results, skipped = normalize(organic)
      if results.empty?
        raise SearchProvider::Error.new("organic_results has no usable entries", category: :schema, http_status: 200)
      end

      SearchProvider::Response.new(results: results, empty: false, search_id: search_id, skipped_count: skipped)
    end

    def empty_response(search_id)
      SearchProvider::Response.new(results: [], empty: true, search_id: search_id, skipped_count: 0)
    end

    # Entries without a usable http(s) link are skipped and counted, not guessed.
    def normalize(organic)
      used_positions = Set.new
      skipped = 0

      results = organic.filter_map do |item|
        url = item.is_a?(Hash) ? item["link"].to_s.strip : ""
        unless usable_url?(url)
          skipped += 1
          next
        end

        position = pick_position(item["position"], used_positions)
        used_positions << position
        SearchProvider::Result.new(
          position: position,
          title: text_or_nil(item["title"], SearchResult::TITLE_MAX_LENGTH),
          url: url,
          display_domain: DomainNormalizer.call(url),
          snippet: text_or_nil(item["snippet"], SearchResult::SNIPPET_MAX_LENGTH),
          extra: extra_for(item)
        )
      end

      [ results, skipped ]
    end

    # Use SerpApi's position when it is a unique positive integer, otherwise the next free one.
    def pick_position(value, used)
      return value if value.is_a?(Integer) && value >= 1 && !used.include?(value)

      (used.max || 0) + 1
    end

    def usable_url?(url)
      return false if url.empty? || url.length > URL_MAX_LENGTH

      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def text_or_nil(value, limit)
      text = value.to_s.strip
      text.empty? ? nil : text.first(limit)
    end

    def extra_for(item)
      displayed = text_or_nil(item["displayed_link"], DISPLAYED_LINK_MAX_LENGTH)
      displayed ? { "displayed_link" => displayed } : {}
    end

    # The upstream message is shown to operators, so the key is redacted defensively.
    def error_message(body)
      return "" unless body.is_a?(Hash)

      body["error"].to_s.gsub(@api_key, "[FILTERED]").first(200)
    end
  end
end
