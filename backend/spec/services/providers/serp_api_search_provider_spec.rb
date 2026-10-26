require "rails_helper"

RSpec.describe Providers::SerpApiSearchProvider do
  subject(:provider) { described_class.new(api_key: api_key) }

  let(:api_key) { "test-key-1234567890" }
  let(:request) do
    SearchProvider::Request.new(query: "react developer", engine: "google", country: "ph", language: "en", location: "Manila")
  end

  def error_from
    yield
    nil
  rescue SearchProvider::Error => e
    e
  end

  describe "configuration" do
    it "refuses to build without a usable key" do
      [ nil, "", "  ", "replace_me" ].each do |key|
        expect { described_class.new(api_key: key) }.to raise_error(SearchProvider::NotConfigured)
      end
    end

    it "builds from the environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SERPAPI_API_KEY").and_return("env-key-123")

      expect { described_class.from_env }.not_to raise_error
    end

    it "fails closed when the environment holds the placeholder" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SERPAPI_API_KEY").and_return("replace_me")

      expect { described_class.from_env }.to raise_error(SearchProvider::NotConfigured)
    end
  end

  describe "outgoing request" do
    it "sends only the documented parameters to the fixed endpoint" do
      stub = stub_request(:get, "https://serpapi.com/search")
             .with(query: {
                     "engine" => "google", "q" => "react developer", "gl" => "ph", "hl" => "en",
                     "location" => "Manila", "output" => "json", "api_key" => api_key
                   })
             .to_return(status: 200, body: serpapi_fixture("success"))

      provider.search(request)

      expect(stub).to have_been_requested.once
    end

    it "omits location when blank and adds no_cache only when enabled" do
      # `query:` with a plain hash matches exactly, so any extra parameter (such as location) would fail this stub.
      stub = stub_request(:get, "https://serpapi.com/search")
             .with(query: { "engine" => "google", "q" => "q", "gl" => "us", "hl" => "en",
                            "output" => "json", "no_cache" => "true", "api_key" => api_key })
             .to_return(status: 200, body: serpapi_fixture("success"))
      bare = SearchProvider::Request.new(query: "q", engine: "google", country: "us", language: "en", location: nil)

      described_class.new(api_key: api_key, no_cache: true).search(bare)

      expect(stub).to have_been_requested.once
    end

    it "does not send no_cache by default" do
      stub = stub_request(:get, "https://serpapi.com/search")
             .with(query: { "engine" => "google", "q" => "q", "gl" => "us", "hl" => "en",
                            "output" => "json", "api_key" => api_key })
             .to_return(status: 200, body: serpapi_fixture("success"))
      bare = SearchProvider::Request.new(query: "q", engine: "google", country: "us", language: "en", location: nil)

      provider.search(bare)

      expect(stub).to have_been_requested.once
    end

    it "applies explicit open and read timeouts" do
      http = instance_double(Net::HTTP, :use_ssl= => nil, :open_timeout= => nil, :read_timeout= => nil, :write_timeout= => nil)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:request).and_return(instance_double(Net::HTTPOK, code: "200", body: serpapi_fixture("success"), "[]": nil))

      described_class.new(api_key: api_key, open_timeout: 2, read_timeout: 7).search(request)

      expect(http).to have_received(:open_timeout=).with(2)
      expect(http).to have_received(:read_timeout=).with(7)
      expect(http).to have_received(:use_ssl=).with(true)
    end
  end

  describe "successful response" do
    before { stub_serpapi(fixture: "success") }

    it "normalizes organic results" do
      response = provider.search(request)

      expect(response.empty).to be(false)
      expect(response.search_id).to eq("fixture-success-1")
      expect(response.skipped_count).to eq(0)
      expect(response.results.map(&:position)).to eq([ 1, 2, 3, 4, 5 ])

      second = response.results[1]
      expect(second.title).to eq("React developer jobs")
      expect(second.url).to eq("https://www.example.com/jobs/react")
      expect(second.display_domain).to eq("example.com")
      expect(second.snippet).to eq("Find remote React roles.")
      expect(second.extra).to eq("displayed_link" => "https://www.example.com › jobs › react")
    end
  end

  describe "empty results" do
    it "treats the documented 200 + error message as a successful empty result" do
      stub_serpapi(fixture: "empty")

      response = provider.search(request)

      expect(response.empty).to be(true)
      expect(response.results).to eq([])
      expect(response.search_id).to eq("fixture-empty-1")
    end

    it "treats a successful response without organic_results as empty" do
      stub_serpapi(fixture: "no_organic_results")

      expect(provider.search(request).empty).to be(true)
    end

    it "treats an empty organic_results array as empty" do
      stub_serpapi(body: { search_metadata: { id: "x", status: "Success" }, organic_results: [] }.to_json)

      expect(provider.search(request).empty).to be(true)
    end
  end

  describe "malformed organic results" do
    def search_with(organic)
      stub_serpapi(body: { search_metadata: { id: "x", status: "Success" }, organic_results: organic }.to_json)
      provider.search(request)
    end

    it "skips entries without a usable link and counts them" do
      response = search_with([
        { "position" => 1, "title" => "no link" },
        { "position" => 2, "title" => "bad scheme", "link" => "javascript:alert(1)" },
        { "position" => 3, "title" => "ok", "link" => "https://example.com/a" },
        "not a hash",
        nil
      ])

      expect(response.results.map(&:url)).to eq([ "https://example.com/a" ])
      expect(response.skipped_count).to eq(4)
    end

    it "keeps order and assigns free positions when position is missing, duplicated, or invalid" do
      response = search_with([
        { "position" => 1, "link" => "https://a.example.com/" },
        { "link" => "https://b.example.com/" },
        { "position" => 2, "link" => "https://c.example.com/" },
        { "position" => 0, "link" => "https://d.example.com/" },
        { "position" => "3", "link" => "https://e.example.com/" }
      ])

      positions = response.results.map(&:position)
      expect(positions).to eq([ 1, 2, 3, 4, 5 ])
      expect(positions.uniq.size).to eq(positions.size)
    end

    it "truncates long text to the model limits instead of failing" do
      response = search_with([
        { "position" => 1, "link" => "https://a.example.com/", "title" => "t" * 900, "snippet" => "s" * 5000,
          "displayed_link" => "d" * 900 }
      ])
      result = response.results.first

      expect(result.title.length).to eq(SearchResult::TITLE_MAX_LENGTH)
      expect(result.snippet.length).to eq(SearchResult::SNIPPET_MAX_LENGTH)
      expect(result.extra["displayed_link"].length).to eq(300)
    end

    it "yields nil display_domain for hosts that are not domains" do
      response = search_with([ { "position" => 1, "link" => "http://10.0.0.5/page" } ])

      expect(response.results.first.display_domain).to be_nil
    end

    it "raises a schema error when entries exist but none is usable" do
      stub_serpapi(body: { search_metadata: { id: "x", status: "Success" }, organic_results: [ { "title" => "x" } ] }.to_json)

      error = error_from { provider.search(request) }

      expect(error.category).to eq(:schema)
    end

    it "raises a schema error when organic_results is not an array" do
      stub_serpapi(body: { search_metadata: { id: "x", status: "Success" }, organic_results: "nope" }.to_json)

      expect(error_from { provider.search(request) }.category).to eq(:schema)
    end
  end

  describe "error classification" do
    {
      [ 400, "missing_query" ] => [ :invalid_request, false ],
      [ 401, "invalid_api_key" ] => [ :auth, false ],
      [ 403, "invalid_api_key" ] => [ :auth, false ],
      [ 429, "out_of_searches" ] => [ :quota, false ],
      [ 503, "server_error" ] => [ :upstream, true ],
      [ 500, "server_error" ] => [ :upstream, true ]
    }.each do |(status, fixture), (category, retryable)|
      it "maps HTTP #{status} (#{fixture}) to #{category}, retryable=#{retryable}" do
        stub_serpapi(fixture: fixture, status: status)

        error = error_from { provider.search(request) }

        expect(error).to be_a(SearchProvider::Error)
        expect(error.category).to eq(category)
        expect(error.retryable?).to be(retryable)
        expect(error.http_status).to eq(status)
      end
    end

    it "maps a 429 that is not about exhausted searches to a retryable rate_limit" do
      # The hourly-limit message text is not documented; only "not the out-of-searches message" is assumed.
      stub_serpapi(body: { error: "Too many requests." }.to_json, status: 429)

      error = error_from { provider.search(request) }

      expect(error.category).to eq(:rate_limit)
      expect(error.retryable?).to be(true)
    end

    it "maps an empty-bodied 429 to rate_limit" do
      stub_serpapi(body: "", status: 429)

      expect(error_from { provider.search(request) }.category).to eq(:rate_limit)
    end

    it "maps HTTP 408 to timeout and unexpected statuses to unknown" do
      stub_serpapi(body: "{}", status: 408)
      expect(error_from { provider.search(request) }.category).to eq(:timeout)

      stub_serpapi(body: "{}", status: 418)
      expect(error_from { provider.search(request) }.category).to eq(:unknown)
    end

    it "handles non-JSON error pages from a proxy without crashing" do
      stub_serpapi(body: "<html>Bad Gateway</html>", status: 502, headers: { "Content-Type" => "text/html" })

      error = error_from { provider.search(request) }

      expect(error.category).to eq(:upstream)
      expect(error.http_status).to eq(502)
    end

    it "detects an error payload even when the HTTP status is 200" do
      stub_serpapi(body: { error: "Invalid API key." }.to_json)
      expect(error_from { provider.search(request) }.category).to eq(:auth)

      stub_serpapi(body: { error: "Your account has run out of searches." }.to_json)
      expect(error_from { provider.search(request) }.category).to eq(:quota)

      stub_serpapi(body: { error: "Missing query `q` parameter." }.to_json)
      expect(error_from { provider.search(request) }.category).to eq(:invalid_request)

      stub_serpapi(body: { error: "Something odd happened." }.to_json)
      error = error_from { provider.search(request) }
      expect(error.category).to eq(:unknown)
      expect(error.retryable?).to be(false)
    end

    it "treats search_metadata.status Error as a retryable upstream failure" do
      stub_serpapi(body: { search_metadata: { id: "x", status: "Error" } }.to_json)

      error = error_from { provider.search(request) }

      expect(error.category).to eq(:upstream)
      expect(error.retryable?).to be(true)
    end

    it "raises a schema error for malformed JSON on HTTP 200" do
      stub_serpapi(body: "{not json")

      expect(error_from { provider.search(request) }.category).to eq(:schema)
    end

    it "raises a schema error for JSON that is not an object" do
      stub_serpapi(body: "[1,2,3]")

      expect(error_from { provider.search(request) }.category).to eq(:schema)
    end

    it "raises a schema error for an unrecognized object" do
      stub_serpapi(body: { "hello" => "world" }.to_json)

      expect(error_from { provider.search(request) }.category).to eq(:schema)
    end

    it "rejects oversized bodies" do
      stub_serpapi(body: "x" * (described_class::MAX_BODY_BYTES + 1))

      expect(error_from { provider.search(request) }.category).to eq(:schema)
    end
  end

  describe "transport failures" do
    it "maps read and connect timeouts to a retryable timeout error" do
      stub_request(:get, /serpapi.com/).to_timeout

      error = error_from { provider.search(request) }

      expect(error.category).to eq(:timeout)
      expect(error.retryable?).to be(true)
    end

    it "maps Net::ReadTimeout to timeout" do
      stub_request(:get, /serpapi.com/).to_raise(Net::ReadTimeout)

      expect(error_from { provider.search(request) }.category).to eq(:timeout)
    end

    it "maps connection failures to a retryable network error" do
      [ Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError, EOFError ].each do |failure|
        stub_request(:get, /serpapi.com/).to_raise(failure)

        error = error_from { provider.search(request) }

        expect(error.category).to eq(:network), "expected #{failure} to map to :network"
        expect(error.retryable?).to be(true)
      end
    end
  end

  describe "secret hygiene" do
    it "never includes the API key in error messages" do
      stub_serpapi(body: { error: "Invalid API key #{api_key} rejected" }.to_json, status: 401)

      error = error_from { provider.search(request) }

      expect(error.message).not_to include(api_key)
      expect(error.message).to include("[FILTERED]")
    end

    it "does not leak the key in transport error messages" do
      stub_request(:get, /serpapi.com/).to_raise(SocketError.new("failed to open #{api_key}"))

      expect(error_from { provider.search(request) }.message).not_to include(api_key)
    end
  end

  describe "Retry-After" do
    it "exposes a delay-in-seconds hint on rate limit errors" do
      stub_serpapi(body: { error: "Too many requests." }.to_json, status: 429, headers: { "Retry-After" => "42" })

      error = error_from { provider.search(request) }

      expect(error.category).to eq(:rate_limit)
      expect(error.retry_after).to eq(42)
    end

    it "also reads it from server errors" do
      stub_serpapi(fixture: "server_error", status: 503, headers: { "Retry-After" => "7" })

      expect(error_from { provider.search(request) }.retry_after).to eq(7)
    end

    it "ignores an HTTP-date, zero, negative, or garbage value" do
      [ "Wed, 21 Oct 2026 07:28:00 GMT", "0", "-5", "soon", "" ].each do |value|
        stub_serpapi(body: "{}", status: 429, headers: { "Retry-After" => value })

        expect(error_from { provider.search(request) }.retry_after).to be_nil
      end
    end

    it "is nil when the header is absent" do
      stub_serpapi(body: "{}", status: 429)

      expect(error_from { provider.search(request) }.retry_after).to be_nil
    end
  end

  describe ".configured?" do
    it "is true for a real-looking key", env: { "SERPAPI_API_KEY" => "abc123" } do
      expect(described_class.configured?).to be(true)
    end

    it "is false for missing, blank, or placeholder keys" do
      [ nil, "", "  ", "replace_me" ].each do |value|
        ENV["SERPAPI_API_KEY"] = value
        expect(described_class.configured?).to be(false)
      end
    ensure
      ENV.delete("SERPAPI_API_KEY")
    end
  end

  describe "#account" do
    let(:account_url) { "https://serpapi.com/account.json" }
    let(:account_body) do
      { account_id: "acc-1", api_key: api_key, account_email: "me@example.com", account_status: "Active",
        plan_name: "Free Plan", searches_per_month: 100, plan_searches_left: 80, total_searches_left: 80,
        this_month_usage: 20, this_hour_searches: 1, last_hour_searches: 0, account_rate_limit_per_hour: 20 }.to_json
    end

    it "returns only the quota fields, never the key or e-mail" do
      stub = stub_request(:get, account_url).with(query: { "api_key" => api_key }).to_return(status: 200, body: account_body)

      result = provider.account

      expect(stub).to have_been_requested.once
      expect(result).to eq(
        "plan_name" => "Free Plan", "searches_per_month" => 100, "plan_searches_left" => 80, "total_searches_left" => 80,
        "this_month_usage" => 20, "this_hour_searches" => 1, "last_hour_searches" => 0, "account_rate_limit_per_hour" => 20
      )
      expect(result.to_json).not_to include(api_key)
      expect(result.to_json).not_to include("me@example.com")
    end

    it "classifies an invalid key as auth" do
      stub_request(:get, /account.json/).to_return(status: 401, body: serpapi_fixture("invalid_api_key"))

      expect(error_from { provider.account }.category).to eq(:auth)
    end

    it "raises a schema error for a malformed body" do
      stub_request(:get, /account.json/).to_return(status: 200, body: "nope")

      expect(error_from { provider.account }.category).to eq(:schema)
    end

    it "maps timeouts like a search does" do
      stub_request(:get, /account.json/).to_timeout

      expect(error_from { provider.account }.category).to eq(:timeout)
    end
  end
end
