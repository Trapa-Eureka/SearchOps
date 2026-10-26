require "rails_helper"

RSpec.describe SearchOpsBenchmark::StubProvider do
  def build(**overrides)
    described_class.new(seed: 7, median_ms: 900, sigma: 0.35, failure_rate: 0.3, sleeper: ->(_seconds) { }, **overrides)
  end

  def request(query: "react developer", country: "ph", language: "en")
    SearchProvider::Request.new(query: query, engine: "google", country: country, language: language, location: nil)
  end

  def attempt(provider, req)
    provider.search(req)
    :ok
  rescue SearchProvider::Error
    :failed
  end

  describe "determinism, so every mode faces the same network" do
    it "gives the same latency and failure for the same search and attempt, whatever happened before" do
      first = build
      second = build
      second.search(request(query: "something else")) rescue nil

      outcomes = [ first, second ].map do |provider|
        attempt(provider, request)
        provider.calls.last
      end

      expect(outcomes.first.latency_ms).to eq(outcomes.last.latency_ms)
      expect(outcomes.first.failed).to eq(outcomes.last.failed)
    end

    it "numbers attempts per search and starts again after reset!" do
      provider = build(failure_rate: 0.0)
      3.times { attempt(provider, request) }
      expect(provider.calls.map(&:attempt)).to eq([ 1, 2, 3 ])

      provider.reset!
      attempt(provider, request)

      expect(provider.calls.map(&:attempt)).to eq([ 1 ])
    end

    it "differs between seeds" do
      latencies = [ 1, 2, 3 ].map { |seed| build(seed: seed).latency_ms("react|ph|en", 1) }

      expect(latencies.uniq.size).to eq(3)
    end
  end

  describe "the latency it samples" do
    it "has the requested median and never exceeds the cap" do
      provider = build
      samples = (1..2000).map { |n| provider.latency_ms("query #{n}|us|en", 1) }

      expect(SearchOpsBenchmark::Stats.percentile(samples, 0.5)).to be_within(60).of(900)
      expect(samples.max).to be <= described_class::MAX_LATENCY_MS
      expect(samples.min).to be > 0
      expect(SearchOpsBenchmark::Stats.percentile(samples, 0.95)).to be > 900 * 1.4
    end

    it "is slept, so measured request times include it" do
      slept = []
      provider = build(failure_rate: 0.0, sleeper: ->(seconds) { slept << seconds })

      provider.search(request)

      expect(slept).to eq([ provider.calls.first.latency_ms / 1000.0 ])
    end

    it "is sampled even for a failing attempt" do
      provider = build(failure_rate: 1.0)

      expect { provider.search(request) }.to raise_error(SearchProvider::Error)
      expect(provider.calls.first.latency_ms).to be > 0
    end
  end

  describe "failures" do
    it "are transient upstream errors that the job retries" do
      provider = build(failure_rate: 1.0)

      error = (provider.search(request) rescue $!)

      expect(error).to be_a(SearchProvider::Error)
      expect(error).to have_attributes(category: :upstream, http_status: 503)
      expect(error.retryable?).to be(true)
    end

    it "happen at about the requested rate" do
      provider = build(failure_rate: 0.3)
      outcomes = (1..2000).map { |n| attempt(provider, request(query: "q#{n}")) }

      expect(outcomes.count(:failed) / 2000.0).to be_within(0.03).of(0.3)
    end

    it "never happen when the rate is zero" do
      provider = build(failure_rate: 0.0)

      expect((1..200).map { |n| attempt(provider, request(query: "q#{n}")) }.uniq).to eq([ :ok ])
    end
  end

  describe "the results" do
    let(:targets) { { "react developer|ph|en" => "react.dev" } }

    it "has five organic results and puts the target domain at its deterministic position" do
      provider = build(failure_rate: 0.0, targets: targets)
      response = provider.search(request)
      position = provider.target_position("react developer|ph|en")

      expect(response.results.size).to eq(5)
      expect(response.empty).to be(false)
      if position
        expect(response.results.find { |result| result.display_domain == "react.dev" }.position).to eq(position)
      else
        expect(response.results.map(&:display_domain)).not_to include("react.dev")
      end
    end

    it "leaves the target out about one time in six (not found), and is otherwise spread over 1..5" do
      provider = build(targets: targets)
      positions = (1..1200).map { |n| provider.target_position("q#{n}|us|en") }

      expect(positions.count(nil) / 1200.0).to be_within(0.04).of(1.0 / 6)
      expect(positions.compact.uniq.sort).to eq([ 1, 2, 3, 4, 5 ])
    end

    it "does not know a target for a search that was not planned" do
      response = build(failure_rate: 0.0, targets: targets).search(request(query: "unplanned"))

      expect(response.results.map(&:display_domain)).to all(match(/\Asite\d\.test\z/))
    end
  end
end
