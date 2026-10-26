require "rails_helper"

RSpec.describe ExecuteSearchJob, env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "100" } do
  let(:keyword) { create(:keyword, target_domain: "example.com") }
  let(:run) { create(:search_run, :queued, keyword: keyword, request_metadata: { "provider" => "serpapi" }) }
  let(:provider) { instance_double(Providers::SerpApiSearchProvider) }

  def result(position, url)
    SearchProvider::Result.new(position: position, title: "T", url: url, display_domain: DomainNormalizer.call(url), snippet: "s", extra: {})
  end

  let(:good_response) do
    SearchProvider::Response.new(results: [ result(1, "https://react.dev/"), result(2, "https://example.com/a") ],
                                 empty: false, search_id: "sid", skipped_count: 0)
  end

  def error(category, http_status: nil, retry_after: nil)
    SearchProvider::Error.new("boom #{category}", category: category, http_status: http_status, retry_after: retry_after)
  end

  before { allow(Providers::SerpApiSearchProvider).to receive(:from_env).and_return(provider) }

  it "is queued on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "limits how many searches run against SerpApi at once" do
    expect(described_class.concurrency_limit).to eq(2)
    expect(described_class.concurrency_key.call(1)).to eq("serpapi_search")
  end

  describe "success" do
    it "runs the search and records the result" do
      allow(provider).to receive(:search).and_return(good_response)

      described_class.perform_now(run.id)

      expect(run.reload).to have_attributes(status: "succeeded", attempts: 1, upstream_calls: 1)
      expect(run.rank_snapshot.rank).to eq(2)
      expect(described_class).not_to have_been_enqueued
    end
  end

  describe "idempotency" do
    it "ignores a run that no longer exists" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end

    it "ignores runs that are not queued and never calls the provider" do
      allow(provider).to receive(:search)
      %w[running succeeded failed].each do |status|
        other = create(:search_run, keyword: keyword, status: status, fingerprint: "fp-#{status}")
        described_class.perform_now(other.id)
      end

      expect(provider).not_to have_received(:search)
    end

    it "calls the provider once when the same job is delivered twice" do
      allow(provider).to receive(:search).and_return(good_response)

      2.times { described_class.perform_now(run.id) }

      expect(provider).to have_received(:search).once
      expect(run.reload.upstream_calls).to eq(1)
    end
  end

  describe "transient failures" do
    %i[timeout network rate_limit upstream].each do |category|
      it "retries a #{category} error and records the attempt" do
        allow(provider).to receive(:search).and_raise(error(category, http_status: 503))

        described_class.perform_now(run.id)

        run.reload
        expect(run).to have_attributes(status: "queued", attempts: 1, upstream_calls: 1, finished_at: nil, error_category: nil)
        expect(run.request_metadata["attempt_log"]).to contain_exactly(
          a_hash_including("attempt" => 1, "category" => category.to_s, "http_status" => 503)
        )
        expect(run.request_metadata["next_retry_in_seconds"]).to be > 0
        expect(described_class).to have_been_enqueued.with(run.id)
      end
    end

    it "schedules the retry in the future with a backoff delay" do
      allow(provider).to receive(:search).and_raise(error(:timeout))
      freeze_time = Time.current

      described_class.perform_now(run.id)

      scheduled = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(scheduled["scheduled_at"] || scheduled[:at]).to be_present
      delay = Time.zone.parse((scheduled["scheduled_at"] || Time.zone.at(scheduled[:at])).to_s) - freeze_time
      expect(delay).to be_between(0.5, 2.5)
    end

    it "honors Retry-After when the server sent one" do
      allow(provider).to receive(:search).and_raise(error(:rate_limit, http_status: 429, retry_after: 90))
      before = Time.current

      described_class.perform_now(run.id)

      scheduled = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      at = Time.zone.parse(scheduled["scheduled_at"].to_s)
      expect(at - before).to be_between(89, 92)
      expect(run.reload.request_metadata["next_retry_in_seconds"]).to eq(90)
    end

    it "gives up after the maximum number of attempts and records the final failure" do
      allow(provider).to receive(:search).and_raise(error(:timeout))

      described_class::MAX_ATTEMPTS.times { described_class.perform_now(run.id) }

      run.reload
      expect(run).to have_attributes(status: "failed", error_category: "timeout", attempts: 3, upstream_calls: 3)
      expect(run.finished_at).to be_present
      expect(run.request_metadata["attempt_log"].size).to eq(3)
      expect(run.request_metadata["error_message"]).to include("timeout")
      expect(provider).to have_received(:search).exactly(3).times
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(2) # retries 1 and 2 only
    end

    it "succeeds on a later attempt and keeps the attempt history" do
      calls = 0
      allow(provider).to receive(:search) do
        calls += 1
        raise error(:upstream, http_status: 503) if calls == 1

        good_response
      end

      2.times { described_class.perform_now(run.id) }

      run.reload
      expect(run).to have_attributes(status: "succeeded", attempts: 2, upstream_calls: 2, error_category: nil)
      expect(run.request_metadata["attempt_log"].size).to eq(1)
      expect(run.search_results.count).to eq(2)
    end
  end

  describe "permanent failures" do
    %i[auth quota invalid_request schema unknown].each do |category|
      it "fails #{category} immediately without retrying" do
        allow(provider).to receive(:search).and_raise(error(category, http_status: 400))

        described_class.perform_now(run.id)

        expect(run.reload).to have_attributes(status: "failed", error_category: category.to_s, attempts: 1, upstream_calls: 1)
        expect(provider).to have_received(:search).once
        expect(described_class).not_to have_been_enqueued
      end
    end
  end

  describe "preserving the last good data" do
    it "leaves the previous successful run, results, and snapshot untouched when a later run fails" do
      allow(provider).to receive(:search).and_return(good_response)
      described_class.perform_now(run.id)
      good = run.reload

      later = create(:search_run, :queued, keyword: keyword, fingerprint: "fp-later")
      allow(provider).to receive(:search).and_raise(error(:auth, http_status: 401))
      described_class.perform_now(later.id)

      expect(later.reload.status).to eq("failed")
      expect(good.reload.status).to eq("succeeded")
      expect(good.search_results.count).to eq(2)
      expect(keyword.rank_snapshots.pluck(:rank)).to eq([ 2 ])
      expect(KeywordFreshness.for(keyword)[keyword.id]).to have_attributes(state: "stale", reason: "last_attempt_failed")
    end
  end

  describe "the budget" do
    it "fails the run as budget without calling the provider when nothing is left", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      create(:search_run, upstream_calls: 1)
      allow(provider).to receive(:search)

      described_class.perform_now(run.id)

      expect(provider).not_to have_received(:search)
      expect(run.reload).to have_attributes(status: "failed", error_category: "budget", upstream_calls: 0)
      expect(described_class).not_to have_been_enqueued
    end

    it "stops retrying once a retry would exceed the budget", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      allow(provider).to receive(:search).and_raise(error(:timeout))

      described_class.perform_now(run.id) # uses the only call, schedules a retry
      described_class.perform_now(run.id) # the retry finds the budget spent

      expect(run.reload).to have_attributes(status: "failed", error_category: "budget", upstream_calls: 1, attempts: 1)
      expect(provider).to have_received(:search).once
    end
  end

  describe "missing credentials" do
    it "fails the run as auth without calling the provider" do
      allow(Providers::SerpApiSearchProvider).to receive(:from_env).and_raise(SearchProvider::NotConfigured)

      described_class.perform_now(run.id)

      expect(run.reload).to have_attributes(status: "failed", error_category: "auth", upstream_calls: 0)
    end
  end

  describe "unexpected exceptions" do
    it "fail the run (never stuck running) and propagate so the job backend records them" do
      allow(provider).to receive(:search).and_raise(NoMethodError, "bug")

      expect { described_class.perform_now(run.id) }.to raise_error(NoMethodError)

      expect(run.reload).to have_attributes(status: "failed", error_category: "unknown")
    end
  end

  describe "the provider factory" do
    around do |example|
      original = described_class.provider_factory
      example.run
    ensure
      described_class.provider_factory = original
    end

    it "builds the SerpApi provider from the environment by default", env: { "SERPAPI_API_KEY" => "factory-spec-key-1234" } do
      allow(Providers::SerpApiSearchProvider).to receive(:from_env).and_call_original # the rest of this file stubs it

      expect(described_class.provider_factory.call).to be_a(Providers::SerpApiSearchProvider)
    end

    it "can be replaced, and then no SerpApi request is made at all" do
      run = create(:search_run, :queued)
      stand_in = instance_double(Providers::SerpApiSearchProvider)
      allow(stand_in).to receive(:search).and_return(SearchProvider::Response.new(results: [], empty: true, search_id: "x", skipped_count: 0))
      described_class.provider_factory = -> { stand_in }

      described_class.perform_now(run.id)

      expect(stand_in).to have_received(:search).once
      expect(run.reload.status).to eq("succeeded")
      expect(a_request(:any, /serpapi/)).not_to have_been_made
    end

    it "still fails an unconfigured provider cleanly" do
      run = create(:search_run, :queued)
      described_class.provider_factory = -> { raise SearchProvider::NotConfigured }

      described_class.perform_now(run.id)

      expect(run.reload).to have_attributes(status: "failed", error_category: "auth")
    end
  end
end
