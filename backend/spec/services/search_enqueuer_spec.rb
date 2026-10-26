require "rails_helper"

RSpec.describe SearchEnqueuer, env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "10", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
  subject(:enqueuer) { described_class.new }

  let(:keyword) do
    create(:keyword, query: "react developer", country: "ph", language: "en", location: "Manila", target_domain: "example.com")
  end
  let(:fingerprint) { SearchFingerprint.call(SearchProvider::Request.from_keyword(keyword)) }

  def finished_run(finished_at: 5.minutes.ago, metadata: {})
    run = create(:search_run, keyword: keyword, fingerprint: fingerprint, finished_at: finished_at, request_metadata: metadata)
    create(:rank_snapshot, keyword: keyword, search_run: run, target_domain: "example.com", rank: 4, captured_at: finished_at)
    run
  end

  describe "a cache miss" do
    it "creates a queued run and enqueues exactly one job" do
      result = nil
      expect { result = enqueuer.call(keyword) }.to have_enqueued_job(ExecuteSearchJob).exactly(:once)

      run = result.run
      expect(result.outcome).to eq(:enqueued)
      expect(run).to be_persisted
      expect(run).to have_attributes(status: "queued", cache_source: "none", triggered_by: "manual", attempts: 0,
                                     upstream_calls: 0, fingerprint: fingerprint, started_at: nil, finished_at: nil)
      expect(run.request_metadata).to include("provider" => "serpapi", "query" => "react developer", "country" => "ph",
                                              "language" => "en", "location" => "Manila", "engine" => "google")
    end

    it "passes only the run id to the job" do
      result = enqueuer.call(keyword)

      expect(ExecuteSearchJob).to have_been_enqueued.with(result.run.id)
    end

    it "records who triggered it" do
      expect(enqueuer.call(keyword, triggered_by: "scheduled").run.triggered_by).to eq("scheduled")
    end
  end

  describe "a cache hit" do
    let!(:source) { finished_run(metadata: { "search_id" => "sid-9", "result_count" => 7, "empty_results" => false }) }

    it "answers from the recent run without enqueuing or spending budget" do
      result = nil
      expect { result = enqueuer.call(keyword) }.not_to have_enqueued_job

      run = result.run
      expect(result.outcome).to eq(:cache_hit)
      expect(run).to have_attributes(status: "succeeded", cache_source: "app", source_run_id: source.id, upstream_calls: 0, attempts: 0)
      expect(run.started_at).to be_present
      expect(run.finished_at).to be_present
      expect(run.request_metadata).to include("search_id" => "sid-9", "result_count" => 7, "empty_results" => false)
      expect(run.request_metadata["cache_age_seconds"]).to be_between(299, 301)
    end

    it "does not create another rank snapshot (no new data)" do
      expect { enqueuer.call(keyword) }.not_to change(RankSnapshot, :count)
    end

    it "still serves the cache when the daily budget is spent", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      expect(SearchBudget.used_today).to eq(1)

      expect(enqueuer.call(keyword).outcome).to eq(:cache_hit)
    end

    it "does not use the cache when refresh is requested" do
      result = nil
      expect { result = enqueuer.call(keyword, refresh: true) }.to have_enqueued_job(ExecuteSearchJob)

      expect(result.outcome).to eq(:enqueued)
    end

    it "misses once the entry is older than the TTL" do
      source.update_columns(finished_at: 2.hours.ago)

      expect(enqueuer.call(keyword).outcome).to eq(:enqueued)
    end
  end

  describe "an identical run already in flight" do
    it "returns the queued run instead of creating another" do
      existing = create(:search_run, :queued, keyword: keyword, fingerprint: fingerprint)

      result = nil
      expect { result = enqueuer.call(keyword) }.not_to have_enqueued_job
      expect(result.outcome).to eq(:deduplicated)
      expect(result.run).to eq(existing)
      expect(keyword.search_runs.count).to eq(1)
    end

    it "also deduplicates against a running run, even with refresh" do
      existing = create(:search_run, :running, keyword: keyword, fingerprint: fingerprint)

      result = enqueuer.call(keyword, refresh: true)

      expect(result.outcome).to eq(:deduplicated)
      expect(result.run).to eq(existing)
    end

    it "deduplicates when another request wins the race for the unique index" do
      winner = create(:search_run, :queued, keyword: keyword, fingerprint: fingerprint)
      allow(enqueuer).to receive(:active_run).and_return(nil, winner)

      result = enqueuer.call(keyword)

      expect(result.outcome).to eq(:deduplicated)
      expect(result.run).to eq(winner)
      expect(keyword.search_runs.count).to eq(1)
    end

    it "does not block a different keyword or different settings" do
      create(:search_run, :queued, keyword: keyword, fingerprint: fingerprint)
      other = create(:keyword, query: "vue developer")

      expect(enqueuer.call(other).outcome).to eq(:enqueued)
    end

    it "is enforced by the database as well" do
      create(:search_run, :queued, keyword: keyword, fingerprint: fingerprint)

      expect { create(:search_run, :running, keyword: keyword, fingerprint: fingerprint) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new run once the previous one has finished" do
      create(:search_run, :failed, keyword: keyword, fingerprint: fingerprint)

      expect(enqueuer.call(keyword).outcome).to eq(:enqueued)
    end
  end

  describe "the daily budget" do
    it "refuses to enqueue and creates nothing once the budget is spent", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      create(:search_run, upstream_calls: 1)

      expect do
        expect { enqueuer.call(keyword) }.to raise_error(SearchBudget::Exceeded)
      end.not_to change(SearchRun, :count)
      expect(ExecuteSearchJob).not_to have_been_enqueued
    end

    it "counts the run it just queued as a reservation", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      enqueuer.call(keyword)
      other = create(:keyword, query: "another query")

      expect { enqueuer.call(other) }.to raise_error(SearchBudget::Exceeded)
    end
  end
end
