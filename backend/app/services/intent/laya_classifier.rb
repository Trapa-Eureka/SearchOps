require "net/http"
require "json"

module Intent
  # Client for laya-serve (POST /v1/systemone). The contract was read from laya/serve.py of
  # laya 0.4.15; see docs/laya-contract.md. The URL comes from the operator's environment, never
  # from a request, and the client only sends the user's sentence and fixed question definitions.
  #
  # Laya answers typed questions about a text. It does not generate text, so nothing it returns
  # is an instruction: the answer is checked against the known labels and is only a proposal.
  class LayaClassifier
    MAX_STATE_LENGTH = IntentRequest::TEXT_MAX_LENGTH
    MAX_BODY_BYTES = 256 * 1024
    PATH = "/v1/systemone".freeze

    def self.from_env
      new(url: Config.url, api_key: Config.api_key, model: Config.model, timeout: Config.timeout_seconds)
    end

    def initialize(url:, model:, timeout:, api_key: nil)
      base = parse_base(url)
      @uri = URI.join(base.to_s.end_with?("/") ? base.to_s : "#{base}/", PATH.delete_prefix("/"))

      @model = model
      @timeout = timeout
      @api_key = api_key
    end

    # Never returns a partial answer: it either returns a Classification or raises ClassifierError.
    def classify(text)
      started = monotonic_ms
      response = post(request_body(text))
      parse(response, monotonic_ms - started)
    end

    private

    def parse_base(url)
      base = URI.parse(url.to_s.strip)
      raise ArgumentError, "LAYA_URL must be an http or https URL" unless base.is_a?(URI::HTTP) && base.host.present?

      base
    rescue URI::InvalidURIError
      raise ArgumentError, "LAYA_URL must be an http or https URL"
    end

    def request_body(text)
      { model: @model, state: text.to_s.first(MAX_STATE_LENGTH), questions: Catalog.questions }
    end

    def post(body)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = @uri.scheme == "https"
      http.open_timeout = [ @timeout, 2 ].min
      http.read_timeout = @timeout
      http.write_timeout = @timeout

      request = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json", "Accept" => "application/json")
      request["Authorization"] = "Bearer #{@api_key}" if @api_key
      request.body = JSON.generate(body)
      http.request(request)
    rescue Timeout::Error
      raise ClassifierError.new("Laya request timed out", category: :timeout)
    rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError
      raise ClassifierError.new("Laya is not reachable", category: :unavailable)
    end

    def parse(response, latency_ms)
      status = response.code.to_i
      raise error_for_status(status) unless status == 200

      body = decode(response.body)
      answers = body.is_a?(Hash) ? body["answers"] : nil
      raise invalid("response has no answers") unless answers.is_a?(Hash)

      intent_answer = answers["intent"]
      probabilities = intent_answer.is_a?(Hash) ? intent_answer["probabilities"] : nil
      probabilities = normalize_probabilities(probabilities)
      intent = intent_answer["choice"]
      raise invalid("unknown intent label") unless Catalog::INTENTS.include?(intent)

      Classification.new(
        intent: intent,
        confidence: probabilities.fetch(intent),
        probabilities: probabilities,
        model: model_name(body),
        latency_ms: latency_ms
      )
    end

    def decode(raw)
      text = raw.to_s
      raise invalid("response is too large") if text.bytesize > MAX_BODY_BYTES

      JSON.parse(text)
    rescue JSON::ParserError
      raise invalid("response is not JSON")
    end

    # Every known label must have a number between 0 and 1; anything else is not trusted.
    def normalize_probabilities(probabilities)
      raise invalid("probabilities missing") unless probabilities.is_a?(Hash)

      Catalog::INTENTS.to_h do |label|
        value = probabilities[label]
        raise invalid("probability for #{label} missing") unless value.is_a?(Numeric) && value.between?(0, 1)

        [ label, value.to_f ]
      end
    end

    def model_name(body)
      routed = body.dig("routing", "model") if body["routing"].is_a?(Hash)
      (routed.presence || @model).to_s.first(50)
    end

    def error_for_status(status)
      category =
        case status
        when 401 then :auth
        when 503 then :busy
        when 400, 413, 422 then :bad_request
        when 500..599 then :server_error
        else :server_error
        end
      ClassifierError.new("Laya returned HTTP #{status}", category: category)
    end

    def invalid(message)
      ClassifierError.new("Laya response rejected: #{message}", category: :invalid_response)
    end

    def monotonic_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
    end
  end
end
