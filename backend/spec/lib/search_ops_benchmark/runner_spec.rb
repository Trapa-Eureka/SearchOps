require "rails_helper"

# A small end-to-end run of the whole benchmark: the real Rails stack and jobs, the real Laya client
# against a stubbed server, no sleeping. It checks that the harness measures what it claims to.
RSpec.describe SearchOpsBenchmark::Runner do
  let(:laya_url) { "http://127.0.0.1:8765/v1/systemone" }
  let(:items) do
    [
      { "id" => 1, "lang" => "en", "intent" => "organic_rank_tracking", "text" => "Where does stripe.com rank for 'payment api' in the United States?",
        "task" => { "query" => "payment api", "country" => "us", "language" => "en", "target_domain" => "stripe.com" } },
      { "id" => 2, "lang" => "en", "intent" => "organic_rank_tracking", "text" => "Where does notion.so rank for 'team wiki'?",
        "task" => { "query" => "team wiki", "country" => "gb", "language" => "en", "target_domain" => "notion.so" } },
      { "id" => 3, "lang" => "en", "intent" => "unsupported", "text" => "Tell me a joke." },
      # Laya will misread this history request as a rank check, which the careless person confirms.
      { "id" => 4, "lang" => "en", "intent" => "search_history", "text" => "Where does vercel.com rank for 'nextjs hosting' in Australia?" }
    ]
  end
  let(:config) { described_class::Config.new(seed: 1, repeats: 1, provider_median_ms: 5, provider_sigma: 0.1, failure_rate: 0.0, hang_samples: 1, laya_url: nil) }
  let(:runner) { described_class.new(items: items, config: config, sleeper: ->(_seconds) { }, out: StringIO.new, allowed_databases: %w[_test]) }
  let(:result) { runner.run }

  def mode(name, policy = nil)
    result[:repetitions].first[:modes].find { |entry| entry[:name] == name && entry[:policy] == policy }[:records]
  end

  before do
    stub_request(:post, laya_url).to_return do |request|
      state = JSON.parse(request.body)["state"]
      intent = state.include?("joke") ? "unsupported" : "organic_rank_tracking"
      { status: 200, body: laya_response_body(intent: intent, confidence: 0.95).to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  around do |example|
    ENV["LAYA_TIMEOUT_SECONDS"] = "0.3"
    example.run
  ensure
    ENV.delete("LAYA_TIMEOUT_SECONDS")
  end

  it "refuses to run on a database that is not a scratch database" do
    expect { described_class.new(items: items, config: config, out: StringIO.new).run }.to raise_error(SearchOpsBenchmark::DatabaseGuard::Refused)
    expect(Keyword.count).to eq(0)
  end

  it "runs every mode, each from an empty database, and leaves the environment as it found it" do
    adapter = ActiveJob::Base.queue_adapter
    factory = ExecuteSearchJob.provider_factory
    env = ENV.to_h.slice("SERPAPI_API_KEY", "LAYA_ENABLED", "LAYA_URL", "SEARCH_MAX_REQUESTS_PER_DAY")

    modes = result[:repetitions].first[:modes].map { |entry| [ entry[:name], entry[:policy] ] }

    expect(modes).to eq([ [ "A", nil ], [ "B", "diligent" ], [ "B", "careless" ], [ "C", "laya refusing connections" ], [ "C", "laya hanging" ] ])
    expect(ActiveJob::Base.queue_adapter).to equal(adapter)
    expect(ExecuteSearchJob.provider_factory).to equal(factory)
    expect(ENV.to_h.slice("SERPAPI_API_KEY", "LAYA_ENABLED", "LAYA_URL", "SEARCH_MAX_REQUESTS_PER_DAY")).to eq(env)
  end

  describe "mode A (structured)" do
    it "does every task through the form, then answers the second pass from the cache" do
      records = mode("A")
      cold, warm = records.partition { |rec| rec[:pass] == "cold" }

      expect(cold.size).to eq(2)
      expect(cold).to all(include(correct: true, provider_calls: 1, cache_hit: false))
      expect(cold.map { |rec| rec[:steps].keys }).to all(eq(%w[create_keyword search]))
      expect(warm).to all(include(correct: true, provider_calls: 0, cache_hit: true))
      expect(warm.map { |rec| rec[:steps].keys }).to all(eq(%w[search]))
    end

    it "never asks Laya, not even for the sentences" do
      only_a = described_class.new(items: items, config: config, sleeper: ->(_seconds) { }, out: StringIO.new, allowed_databases: %w[_test], modes: [ "A" ])

      expect(only_a.run[:repetitions].first[:modes].map { |entry| entry[:name] }).to eq([ "A" ])
      expect(a_request(:post, /127\.0\.0\.1/)).not_to have_been_made
    end
  end

  describe "mode B (natural language)" do
    it "confirms the ready plan, completes the one with a missing country, and leaves the joke alone" do
      cold = mode("B", "diligent").select { |rec| rec[:pass] == "cold" }.index_by { |rec| rec[:item_id] }

      expect(cold[1]).to include(plan_status: "ready", decision: "confirm", edits: 0, correct: true, fallback: false)
      expect(cold[2]).to include(plan_status: "needs_clarification", decision: "confirm", correct: true)
      expect(cold[2][:edits]).to be_positive
      expect(cold[3]).to include(decision: "stop", provider_calls: 0, completed: false)
      expect(cold.values.map { |rec| rec[:laya_ms] }.compact).not_to be_empty
    end

    it "keeps the plan and the intended task, so field accuracy can be reported" do
      cold = mode("B", "diligent").select { |entry| entry[:pass] == "cold" }.index_by { |entry| entry[:item_id] }

      expect(cold[1][:plan]).to include("intent" => "organic_rank_tracking", "query" => "payment api", "country" => "us", "target_domain" => "stripe.com")
      expect(cold[1][:task]).to include("country" => "us")
      expect(cold[2][:task]).to include("country" => "gb")
      expect(cold[2][:plan]["country"]).to be_nil # the sentence did not say it
    end

    it "records the time of each step, with the planning step including Laya" do
      rec = mode("B", "diligent").find { |entry| entry[:item_id] == 1 && entry[:pass] == "cold" }

      expect(rec[:steps].keys).to eq(%w[plan confirm])
      expect(rec[:ms]).to be_within(0.001).of(rec[:steps].values.sum)
    end

    it "counts a search that should not have been made when the person confirms without reading" do
      careless = mode("B", "careless").select { |rec| rec[:pass] == "cold" }.index_by { |rec| rec[:item_id] }

      expect(careless[4]).to include(decision: "confirm", executed_kind: "search", has_task: false, provider_calls: 1, unnecessary_calls: 1)
      expect(careless[2][:decision]).to eq("stop") # a plan that needs completing is not confirmed
      expect(careless[1][:unnecessary_calls]).to eq(0)
    end

    it "runs a second pass over the tasks only, served from the cache" do
      warm = mode("B", "diligent").select { |rec| rec[:pass] == "warm" }

      expect(warm.map { |rec| rec[:item_id] }).to eq([ 1, 2 ])
      expect(warm).to all(include(cache_hit: true, provider_calls: 0))
    end
  end

  describe "mode C (Laya unavailable)" do
    it "gives the sentence a fallback, then does the task through the form" do
      cold = mode("C", "laya refusing connections").select { |rec| rec[:pass] == "cold" }.index_by { |rec| rec[:item_id] }

      expect(cold.values.map { |rec| rec[:plan_status] }.uniq).to eq([ "unavailable" ])
      expect(cold[1]).to include(fallback: true, correct: true, provider_calls: 1)
      expect(cold[1][:steps].keys).to eq(%w[plan create_keyword search])
      expect(cold[3]).to include(decision: "stop", provider_calls: 0)
    end

    it "measures how long a person waits when Laya accepts the connection and never answers" do
      rec = mode("C", "laya hanging").first

      expect(rec).to include(plan_status: "unavailable", plan_reason: "classifier_timeout")
      expect(rec[:steps]["plan"]).to be >= 250
      expect(rec[:provider_calls]).to eq(0)
    end
  end

  describe "the report" do
    it "renders every table from what was recorded, without NaN or made-up numbers" do
      text = SearchOpsBenchmark::Report.new(result).markdown

      expect(text).to include("Plan fields against what the person meant", "not provided (asked for)", "Extra time per task compared with the form", "Typing for the rank-check tasks")
      expect(text).to include("B - A, all tasks", "C - A, all tasks")
      expect(text).to include("Getting a rank check done", "Where the time goes", "Natural language (B, diligent)", "Cost of misreadings", "Second pass over the same tasks",
                              "What a person waits", "Cost.")
      expect(text).not_to match(/NaN|Infinity/)
      expect(text).to include("A | 2/2")
    end

    it "serialises to JSON that round-trips" do
      json = SearchOpsBenchmark::Report.new(result).to_json

      expect(JSON.parse(json)).to include("meta", "repetitions")
    end
  end
end
