require "rails_helper"

RSpec.describe SearchOrchestrator do
  subject(:orchestrator) { described_class.new(provider: provider) }

  let(:keyword) { create(:keyword, query: "react developer", country: "ph", language: "en", location: "Manila", target_domain: "example.com") }
  let(:provider) { instance_double(Providers::SerpApiSearchProvider) }

  def result(position, url)
    SearchProvider::Result.new(position: position, title: "T#{position}", url: url, display_domain: DomainNormalizer.call(url),
                               snippet: "s", extra: {})
  end

  def response(results, search_id: "sid-1", skipped: 0)
    SearchProvider::Response.new(results: results, empty: results.empty?, search_id: search_id, skipped_count: skipped)
  end

  let(:window) do
    [ result(1, "https://react.dev/"), result(2, "https://www.example.com/jobs"), result(3, "https://en.wikipedia.org/x") ]
  end

  around do |example|
    original = ENV["SEARCH_MAX_REQUESTS_PER_DAY"]
    ENV["SEARCH_MAX_REQUESTS_PER_DAY"] = "100"
    example.run
  ensure
    original.nil? ? ENV.delete("SEARCH_MAX_REQUESTS_PER_DAY") : ENV["SEARCH_MAX_REQUESTS_PER_DAY"] = original
  end

  describe "successful search" do
    before { allow(provider).to receive(:search).and_return(response(window)) }

    it "records a succeeded run with timing and provenance" do
      run = orchestrator.call(keyword)

      expect(run).to be_persisted
      expect(run.status).to eq("succeeded")
      expect(run.http_status).to eq(200)
      expect(run.error_category).to be_nil
      expect(run.upstream_latency_ms).to be >= 0
      expect(run.started_at).to be <= run.finished_at
      expect(run.fingerprint).to match(/\A\h{64}\z/)
      expect(run.request_metadata).to include(
        "provider" => "serpapi", "engine" => "google", "query" => "react developer", "country" => "ph",
        "language" => "en", "location" => "Manila", "search_id" => "sid-1",
        "result_count" => 3, "empty_results" => false, "skipped_results" => 0
      )
    end

    it "passes a request built from the keyword to the provider" do
      orchestrator.call(keyword)

      expect(provider).to have_received(:search).with(
        SearchProvider::Request.new(query: "react developer", engine: "google", country: "ph", language: "en", location: "Manila")
      )
    end

    it "stores the normalized results in order" do
      run = orchestrator.call(keyword)

      expect(run.search_results.order(:position).pluck(:position, :url)).to eq([
        [ 1, "https://react.dev/" ], [ 2, "https://www.example.com/jobs" ], [ 3, "https://en.wikipedia.org/x" ]
      ])
    end

    it "stores a rank snapshot for the target domain" do
      run = orchestrator.call(keyword)

      snapshot = run.rank_snapshot
      expect(snapshot.keyword).to eq(keyword)
      expect(snapshot.target_domain).to eq("example.com")
      expect(snapshot.rank).to eq(2)
      expect(snapshot.captured_at).to eq(run.finished_at)
    end

    it "stores a null rank when the target is not in the window" do
      keyword.update!(target_domain: "absent.org")

      run = orchestrator.call(keyword)

      expect(run.rank_snapshot.rank).to be_nil
      expect(run.rank_snapshot.found?).to be(false)
    end

    it "stores no snapshot when the keyword has no target domain" do
      keyword.update!(target_domain: nil)

      run = orchestrator.call(keyword)

      expect(run.rank_snapshot).to be_nil
      expect(run.search_results.count).to eq(3)
    end
  end

  describe "empty result" do
    before { allow(provider).to receive(:search).and_return(response([], search_id: "sid-empty")) }

    it "is a succeeded run with zero results and a null rank" do
      run = orchestrator.call(keyword)

      expect(run.status).to eq("succeeded")
      expect(run.search_results.count).to eq(0)
      expect(run.request_metadata).to include("result_count" => 0, "empty_results" => true)
      expect(run.rank_snapshot.rank).to be_nil
    end
  end

  describe "provider failures" do
    {
      timeout: [ nil, true ], network: [ nil, true ], upstream: [ 503, true ],
      rate_limit: [ 429, true ], quota: [ 429, false ], auth: [ 401, false ],
      invalid_request: [ 400, false ], schema: [ 200, false ], unknown: [ 200, false ]
    }.each do |category, (http_status, _retryable)|
      it "records a failed run for #{category} errors without raising" do
        allow(provider).to receive(:search)
          .and_raise(SearchProvider::Error.new("boom (#{category})", category: category, http_status: http_status))

        run = nil
        expect { run = orchestrator.call(keyword) }.not_to raise_error

        expect(run.status).to eq("failed")
        expect(run.error_category).to eq(category.to_s)
        expect(run.http_status).to eq(http_status)
        expect(run.finished_at).to be_present
        expect(run.upstream_latency_ms).to be >= 0
        expect(run.request_metadata["error_message"]).to eq("boom (#{category})")
        expect(run.search_results.count).to eq(0)
        expect(run.rank_snapshot).to be_nil
      end
    end

    it "keeps earlier successful data when a later search fails" do
      allow(provider).to receive(:search).and_return(response(window))
      good = orchestrator.call(keyword)

      allow(provider).to receive(:search).and_raise(SearchProvider::Error.new("down", category: :upstream, http_status: 503))
      bad = orchestrator.call(keyword)

      expect(bad.status).to eq("failed")
      expect(good.reload.status).to eq("succeeded")
      expect(good.search_results.count).to eq(3)
      expect(good.rank_snapshot.rank).to eq(2)
      expect(keyword.rank_snapshots.count).to eq(1)
    end

    it "marks provider output rejected by our validations as a schema failure and stores nothing partial" do
      too_long = result(1, "https://a.example.com/").with(url: "https://a.example.com/#{'x' * 3000}")
      allow(provider).to receive(:search).and_return(response([ window.first, too_long ]))

      run = orchestrator.call(keyword)

      expect(run.status).to eq("failed")
      expect(run.error_category).to eq("schema")
      expect(run.search_results.count).to eq(0)
      expect(run.rank_snapshot).to be_nil
    end

    it "never leaves a run in 'running' when something unexpected breaks, and re-raises" do
      allow(provider).to receive(:search).and_raise(NoMethodError, "bug")

      expect { orchestrator.call(keyword) }.to raise_error(NoMethodError)

      run = keyword.search_runs.last
      expect(run.status).to eq("failed")
      expect(run.error_category).to eq("unknown")
      expect(run.finished_at).to be_present
    end
  end

  describe "budget" do
    it "refuses to search, creates no run, and never calls the provider once the budget is spent" do
      ENV["SEARCH_MAX_REQUESTS_PER_DAY"] = "1"
      create(:search_run)
      allow(provider).to receive(:search)

      expect { orchestrator.call(keyword) }.to raise_error(SearchBudget::Exceeded)

      expect(provider).not_to have_received(:search)
      expect(keyword.search_runs.count).to eq(0)
    end
  end

  describe "logging" do
    before { allow(provider).to receive(:search).and_return(response(window)) }

    it "logs run id, status, and latency but not the query text" do
      allow(Rails.logger).to receive(:info)

      run = orchestrator.call(keyword)

      expect(Rails.logger).to have_received(:info).with(a_string_matching(/search_run run_id=#{run.id} .*status=succeeded .*latency_ms=\d+/))
      expect(Rails.logger).not_to have_received(:info).with(a_string_including("react developer"))
    end

    it "logs the error category for failures" do
      allow(provider).to receive(:search).and_raise(SearchProvider::Error.new("x", category: :timeout))
      allow(Rails.logger).to receive(:info)

      orchestrator.call(keyword)

      expect(Rails.logger).to have_received(:info).with(a_string_matching(/status=failed error_category=timeout/))
    end
  end
end
