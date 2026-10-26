require "rails_helper"

RSpec.describe SearchOrchestrator, env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "100" } do
  subject(:orchestrator) { described_class.new(provider: provider) }

  let(:keyword) { create(:keyword, query: "react developer", country: "ph", language: "en", location: "Manila", target_domain: "example.com") }
  let(:run) { create(:search_run, :queued, keyword: keyword, request_metadata: { "provider" => "serpapi", "query" => "react developer" }) }
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

  describe "a successful attempt" do
    before { allow(provider).to receive(:search).and_return(response(window)) }

    it "returns a succeeded attempt and records the run with timing and counters" do
      attempt = orchestrator.execute(run)

      expect(attempt.status).to eq(:succeeded)
      expect(attempt.error).to be_nil
      expect(attempt.latency_ms).to be >= 0
      run.reload
      expect(run).to have_attributes(status: "succeeded", http_status: 200, error_category: nil, attempts: 1, upstream_calls: 1)
      expect(run.upstream_latency_ms).to be >= 0
      expect(run.started_at).to be <= run.finished_at
      expect(run.request_metadata).to include("search_id" => "sid-1", "result_count" => 3, "empty_results" => false,
                                              "skipped_results" => 0, "query" => "react developer")
    end

    it "sends a request built from the keyword" do
      orchestrator.execute(run)

      expect(provider).to have_received(:search).with(
        SearchProvider::Request.new(query: "react developer", engine: "google", country: "ph", language: "en", location: "Manila")
      )
    end

    it "marks the run running while the provider is being called" do
      observed = nil
      allow(provider).to receive(:search) do
        observed = SearchRun.find(run.id).slice(:status, :attempts, :upstream_calls, :started_at).symbolize_keys
        response(window)
      end

      orchestrator.execute(run)

      expect(observed).to include(status: "running", attempts: 1, upstream_calls: 1)
      expect(observed[:started_at]).to be_present
    end

    it "stores the normalized results in order" do
      orchestrator.execute(run)

      expect(run.search_results.order(:position).pluck(:position, :url)).to eq([
        [ 1, "https://react.dev/" ], [ 2, "https://www.example.com/jobs" ], [ 3, "https://en.wikipedia.org/x" ]
      ])
    end

    it "stores a rank snapshot for the target domain" do
      orchestrator.execute(run)

      snapshot = run.reload.rank_snapshot
      expect(snapshot).to have_attributes(keyword: keyword, target_domain: "example.com", rank: 2)
      expect(snapshot.captured_at).to eq(run.finished_at)
    end

    it "stores a null rank when the target is not in the window" do
      keyword.update!(target_domain: "absent.org")

      orchestrator.execute(run)

      expect(run.reload.rank_snapshot.rank).to be_nil
    end

    it "stores no snapshot when the keyword has no target domain" do
      keyword.update!(target_domain: nil)

      orchestrator.execute(run)

      expect(run.reload.rank_snapshot).to be_nil
      expect(run.search_results.count).to eq(3)
    end
  end

  describe "an empty result" do
    it "is a succeeded run with zero results and a null rank" do
      allow(provider).to receive(:search).and_return(response([], search_id: "sid-empty"))

      orchestrator.execute(run)

      run.reload
      expect(run.status).to eq("succeeded")
      expect(run.search_results.count).to eq(0)
      expect(run.request_metadata).to include("result_count" => 0, "empty_results" => true)
      expect(run.rank_snapshot.rank).to be_nil
    end
  end

  describe "a provider failure" do
    let(:error) { SearchProvider::Error.new("SerpApi returned HTTP 503", category: :upstream, http_status: 503) }

    before { allow(provider).to receive(:search).and_raise(error) }

    it "returns the error without deciding the outcome: the job chooses retry or give up" do
      attempt = orchestrator.execute(run)

      expect(attempt).to have_attributes(status: :failed, error: error)
      expect(attempt.latency_ms).to be >= 0
      expect(run.reload).to have_attributes(status: "running", attempts: 1, upstream_calls: 1, finished_at: nil)
      expect(run.search_results.count).to eq(0)
      expect(run.rank_snapshot).to be_nil
    end
  end

  describe "provider output that fails our validation" do
    it "returns a schema error and stores nothing partial" do
      too_long = result(1, "https://a.example.com/").with(url: "https://a.example.com/#{'x' * 3000}")
      allow(provider).to receive(:search).and_return(response([ window.first, too_long ]))

      attempt = orchestrator.execute(run)

      expect(attempt.status).to eq(:failed)
      expect(attempt.error.category).to eq(:schema)
      expect(attempt.error.retryable?).to be(false)
      expect(run.search_results.count).to eq(0)
      expect(run.reload.rank_snapshot).to be_nil
      expect(run.status).to eq("running")
    end
  end

  describe "an unexpected exception" do
    it "closes the run as failed (never stuck in running) and re-raises" do
      allow(provider).to receive(:search).and_raise(NoMethodError, "bug")

      expect { orchestrator.execute(run) }.to raise_error(NoMethodError)

      expect(run.reload).to have_attributes(status: "failed", error_category: "unknown")
      expect(run.finished_at).to be_present
    end
  end

  describe "claiming" do
    before { allow(provider).to receive(:search).and_return(response(window)) }

    it "skips a run that is not queued and never calls the provider" do
      %w[running succeeded failed].each do |status|
        other = create(:search_run, keyword: keyword, status: status, fingerprint: "fp-#{status}")

        expect(orchestrator.execute(other).status).to eq(:skipped)
      end
      expect(provider).not_to have_received(:search)
    end

    it "lets only one of two executions of the same run reach the provider" do
      stale_copy = SearchRun.find(run.id)

      first = orchestrator.execute(run)
      second = orchestrator.execute(stale_copy)

      expect([ first.status, second.status ]).to eq(%i[succeeded skipped])
      expect(provider).to have_received(:search).once
      expect(run.reload.upstream_calls).to eq(1)
    end

    it "loses the claim cleanly if another worker takes the run between the check and the update" do
      allow(run).to receive(:reload).and_wrap_original do |original, *args|
        original.call(*args).tap { SearchRun.where(id: run.id).update_all(status: "running") }
      end

      expect(orchestrator.execute(run).status).to eq(:skipped)
      expect(provider).not_to have_received(:search)
    end

    it "counts every attempt of a retried run" do
      allow(provider).to receive(:search).and_raise(SearchProvider::Error.new("x", category: :timeout))

      orchestrator.execute(run)
      run.update!(status: "queued")
      orchestrator.execute(run)

      expect(run.reload).to have_attributes(attempts: 2, upstream_calls: 2)
    end
  end

  describe "the budget" do
    it "raises before claiming or calling the provider when the budget is spent", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      create(:search_run, upstream_calls: 1)
      allow(provider).to receive(:search)

      expect { orchestrator.execute(run) }.to raise_error(SearchBudget::Exceeded)

      expect(provider).not_to have_received(:search)
      expect(run.reload).to have_attributes(status: "queued", attempts: 0, upstream_calls: 0)
    end

    it "does not count the run's own reservation against itself", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      allow(provider).to receive(:search).and_return(response(window))

      expect(orchestrator.execute(run).status).to eq(:succeeded)
    end
  end

  describe "logging" do
    before do
      allow(provider).to receive(:search).and_return(response(window))
      allow(Rails.logger).to receive(:info)
    end

    it "logs run id, outcome, and latency but not the query text" do
      orchestrator.execute(run)

      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/search_attempt run_id=#{run.id} keyword_id=\d+ attempt=1 outcome=succeeded .*latency_ms=\d+/))
      expect(Rails.logger).not_to have_received(:info).with(a_string_including("react developer"))
    end

    it "logs the error category for failures" do
      allow(provider).to receive(:search).and_raise(SearchProvider::Error.new("x", category: :timeout))

      orchestrator.execute(run)

      expect(Rails.logger).to have_received(:info).with(a_string_matching(/outcome=failed error_category=timeout/))
    end
  end
end
