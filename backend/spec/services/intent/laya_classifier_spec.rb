require "rails_helper"

RSpec.describe Intent::LayaClassifier do
  subject(:classifier) { described_class.new(url: "http://127.0.0.1:8765", model: "multilingual", timeout: 2) }

  let(:url) { "http://127.0.0.1:8765/v1/systemone" }
  let(:example) { "필리핀에서 Senior React Developer 원격 채용공고를 찾아서 지난주와 비교해 새 공고만 보여줘." }

  def error_from
    yield
    nil
  rescue Intent::ClassifierError => e
    e
  end

  describe "the request" do
    it "matches the recorded request body exactly" do
      recorded = JSON.parse(Rails.root.join("spec/fixtures/laya/systemone_request.json").read)
      stub = stub_request(:post, url).with(body: recorded.to_json).to_return(status: 200, body: Rails.root.join("spec/fixtures/laya/systemone_response.json").read)

      classifier.classify(example)

      expect(stub).to have_been_requested.once
    end

    it "asks one choice question over exactly the four intents" do
      stub_laya
      classifier.classify("hello")

      expect(a_request(:post, url).with { |req|
        question = JSON.parse(req.body).dig("questions", "intent")
        JSON.parse(req.body)["questions"].keys == [ "intent" ] && question["type"] == "choice" &&
          question["criteria"].keys == Intent::Catalog::INTENTS
      }).to have_been_made
    end

    it "sends JSON to the configured model and nothing else from the caller" do
      stub_laya
      classifier.classify("hello")

      expect(a_request(:post, url).with { |req| JSON.parse(req.body).keys.sort == %w[model questions state] && JSON.parse(req.body)["model"] == "multilingual" }).to have_been_made
    end

    it "sends a bearer token only when a key is configured" do
      stub_laya
      described_class.new(url: "http://127.0.0.1:8765", model: "multilingual", timeout: 2, api_key: "laya-secret-1").classify("hello")
      classifier.classify("hello")

      expect(a_request(:post, url).with(headers: { "Authorization" => "Bearer laya-secret-1" })).to have_been_made.once
      expect(a_request(:post, url).with { |req| req.headers["Authorization"].nil? }).to have_been_made.once
    end

    it "caps the text at the maximum request length" do
      stub_laya
      classifier.classify("a" * 5_000)

      expect(a_request(:post, url).with { |req| JSON.parse(req.body)["state"].length == IntentRequest::TEXT_MAX_LENGTH }).to have_been_made
    end

    it "accepts a URL with a trailing slash or a path prefix" do
      stub = stub_request(:post, "http://laya.internal:9000/prefix/v1/systemone").to_return(status: 200, body: laya_response_body(intent: "job_search").to_json)

      described_class.new(url: "http://laya.internal:9000/prefix", model: "multilingual", timeout: 2).classify("x")

      expect(stub).to have_been_requested
    end

    it "refuses a URL that is not http or https" do
      expect { described_class.new(url: "file:///etc/passwd", model: "multilingual", timeout: 2) }.to raise_error(ArgumentError)
      expect { described_class.new(url: "ftp://example.com", model: "multilingual", timeout: 2) }.to raise_error(ArgumentError)
    end

    it "applies explicit timeouts" do
      http = instance_double(Net::HTTP, :use_ssl= => nil, :open_timeout= => nil, :read_timeout= => nil, :write_timeout= => nil)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:request).and_return(instance_double(Net::HTTPOK, code: "200", body: laya_response_body(intent: "job_search").to_json))

      described_class.new(url: "http://127.0.0.1:8765", model: "multilingual", timeout: 3).classify("x")

      expect(http).to have_received(:read_timeout=).with(3)
      expect(http).to have_received(:open_timeout=).with(2)
    end
  end

  describe "the recorded real response" do
    before { stub_request(:post, url).to_return(status: 200, body: Rails.root.join("spec/fixtures/laya/systemone_response.json").read) }

    it "is parsed into a classification" do
      result = classifier.classify(example)

      expect(result.intent).to eq("unsupported")
      expect(result.confidence).to be_within(0.001).of(0.5646)
      expect(result.probabilities.keys).to eq(Intent::Catalog::INTENTS)
      expect(result.probabilities["job_search"]).to be_within(0.001).of(0.3931)
      expect(result.model).to eq("multilingual")
      expect(result.latency_ms).to be >= 0
    end
  end

  describe "a good response" do
    it "uses the probability of the chosen label as the confidence" do
      stub_laya(intent: "search_history", confidence: 0.83)

      result = classifier.classify("x")

      expect([ result.intent, result.confidence ]).to eq([ "search_history", 0.83 ])
    end

    it "falls back to the requested model name when routing is absent" do
      body = laya_response_body(intent: "job_search")
      body.delete("routing")
      stub_laya(body: body)

      expect(classifier.classify("x").model).to eq("multilingual")
    end
  end

  describe "failures" do
    {
      401 => :auth, 400 => :bad_request, 413 => :bad_request, 422 => :bad_request,
      503 => :busy, 500 => :server_error, 502 => :server_error, 404 => :server_error
    }.each do |status, category|
      it "maps HTTP #{status} to #{category}" do
        stub_request(:post, url).to_return(status: status, body: { detail: "nope" }.to_json)

        expect(error_from { classifier.classify("x") }.category).to eq(category)
      end
    end

    it "maps a timeout" do
      stub_request(:post, url).to_timeout

      expect(error_from { classifier.classify("x") }.category).to eq(:timeout)
    end

    it "maps connection failures to unavailable" do
      [ Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, EOFError ].each do |failure|
        stub_request(:post, url).to_raise(failure)

        expect(error_from { classifier.classify("x") }.category).to eq(:unavailable), "expected #{failure}"
      end
    end

    it "rejects a body that is not JSON" do
      stub_laya(body: "<html>oops</html>")

      expect(error_from { classifier.classify("x") }.category).to eq(:invalid_response)
    end

    it "rejects JSON without answers" do
      stub_laya(body: { "model" => "x" })

      expect(error_from { classifier.classify("x") }.category).to eq(:invalid_response)
    end

    it "rejects an unknown intent label instead of passing it on" do
      body = laya_response_body(intent: "job_search")
      body["answers"]["intent"]["choice"] = "delete_everything"
      stub_laya(body: body)

      expect(error_from { classifier.classify("x") }.category).to eq(:invalid_response)
    end

    it "rejects missing, non-numeric, or out-of-range probabilities" do
      [ nil, "0.9", -0.1, 1.5 ].each do |bad|
        body = laya_response_body(intent: "job_search")
        body["answers"]["intent"]["probabilities"]["job_search"] = bad
        stub_laya(body: body)

        expect(error_from { classifier.classify("x") }.category).to eq(:invalid_response), "expected #{bad.inspect} to be rejected"
      end
    end

    it "rejects a missing probabilities object" do
      body = laya_response_body(intent: "job_search")
      body["answers"]["intent"].delete("probabilities")
      stub_laya(body: body)

      expect(error_from { classifier.classify("x") }.category).to eq(:invalid_response)
    end

    it "rejects oversized responses" do
      stub_laya(body: "x" * (described_class::MAX_BODY_BYTES + 1))

      expect(error_from { classifier.classify("x") }.category).to eq(:invalid_response)
    end

    it "never puts the API key in an error message" do
      stub_request(:post, url).to_return(status: 401, body: "bad key laya-secret-1")

      error = error_from { described_class.new(url: "http://127.0.0.1:8765", model: "multilingual", timeout: 2, api_key: "laya-secret-1").classify("x") }

      expect(error.message).not_to include("laya-secret-1")
    end
  end

  describe "against a real laya-serve", :laya_live do
    it "answers the project example with the documented shape" do
      result = described_class.from_env.classify(example)

      expect(Intent::Catalog::INTENTS).to include(result.intent)
      expect(result.probabilities.values.sum).to be_within(0.05).of(1.0)
      expect(result.latency_ms).to be < 5_000
    end
  end

  describe "the address" do
    it "accepts only http and https URLs, so an operator typo cannot point it at a file or another protocol" do
      [ "file:///etc/passwd", "ftp://127.0.0.1/", "javascript:alert(1)", "gopher://127.0.0.1:70/", "127.0.0.1:8765", "http://", "", nil, "http://exa mple.com" ].each do |url|
        expect { described_class.new(url: url, model: "multilingual", timeout: 2) }
          .to raise_error(ArgumentError, "LAYA_URL must be an http or https URL"), "expected #{url.inspect} to be refused"
      end
    end

    it "joins the path whether or not the base ends with a slash, and keeps a base path" do
      stub_request(:post, "http://127.0.0.1:9000/base/v1/systemone")
        .to_return(status: 200, body: Rails.root.join("spec/fixtures/laya/systemone_response.json").read)

      [ "http://127.0.0.1:9000/base", "http://127.0.0.1:9000/base/" ].each_with_index do |url, index|
        described_class.new(url: url, model: "multilingual", timeout: 2).classify("hello")

        expect(a_request(:post, "http://127.0.0.1:9000/base/v1/systemone")).to have_been_made.times(index + 1)
      end
    end

    it "never sends the address the user typed anywhere: the target comes only from configuration" do
      stub = stub_request(:post, url).to_return(status: 200, body: Rails.root.join("spec/fixtures/laya/systemone_response.json").read)

      classifier.classify("http://169.254.169.254/latest/meta-data/ please")

      expect(stub).to have_been_requested.once
      expect(a_request(:any, /169\.254/)).not_to have_been_made
    end
  end

  describe "answers that do not have the expected shape" do
    {
      "a JSON array" => "[]",
      "a JSON string" => '"ok"',
      "no answers" => "{}",
      "answers that are not an object" => '{"answers": []}',
      "an intent answer that is not an object" => '{"answers": {"intent": "organic_rank_tracking"}}',
      "an intent answer without probabilities" => '{"answers": {"intent": {"choice": "organic_rank_tracking"}}}',
      "an unknown label" => '{"answers": {"intent": {"choice": "delete_everything", "probabilities": {"organic_rank_tracking": 1.0}}}}'
    }.each do |name, body|
      it "is an invalid response, not a crash or a guess: #{name}" do
        stub_request(:post, url).to_return(status: 200, body: body)

        error = error_from { classifier.classify("hello") }

        expect(error).to be_a(Intent::ClassifierError)
        expect(error.category).to eq(:invalid_response)
      end
    end
  end
end
