require "rails_helper"

RSpec.describe SearchOpsBenchmark::ImmediateQueueAdapter do
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    original_factory = ExecuteSearchJob.provider_factory
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
    ExecuteSearchJob.provider_factory = original_factory
  end

  let(:adapter) { described_class.new }
  let(:keyword) { create(:keyword, target_domain: "example.com") }
  let(:response) { SearchProvider::Response.new(results: [], empty: true, search_id: "x", skipped_count: 0) }

  before { ActiveJob::Base.queue_adapter = adapter }

  it "runs a job at once, in the calling thread" do
    run = create(:search_run, :queued, keyword: keyword)
    ExecuteSearchJob.provider_factory = -> { instance_double(Providers::SerpApiSearchProvider, search: response) }

    ExecuteSearchJob.perform_later(run.id)

    expect(run.reload.status).to eq("succeeded")
    expect(adapter.delays).to eq([])
  end

  it "runs a retry at once too, and records how long production would have waited", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "100" } do
    run = create(:search_run, :queued, keyword: keyword)
    calls = 0
    provider = instance_double(Providers::SerpApiSearchProvider)
    allow(provider).to receive(:search) do
      calls += 1
      raise SearchProvider::Error.new("flaky", category: :upstream, http_status: 503) if calls < 3

      response
    end
    ExecuteSearchJob.provider_factory = -> { provider }

    ExecuteSearchJob.perform_later(run.id)

    expect(run.reload).to have_attributes(status: "succeeded", attempts: 3)
    expect(adapter.delays.size).to eq(2)
    expect(adapter.delays).to all(be > 0)
    expect(adapter.delays.second).to be > adapter.delays.first # capped exponential backoff grows
  end

  it "stops retrying at the attempt limit, like production", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "100" } do
    run = create(:search_run, :queued, keyword: keyword)
    provider = instance_double(Providers::SerpApiSearchProvider)
    allow(provider).to receive(:search).and_raise(SearchProvider::Error.new("down", category: :upstream, http_status: 503))
    ExecuteSearchJob.provider_factory = -> { provider }

    ExecuteSearchJob.perform_later(run.id)

    expect(run.reload).to have_attributes(status: "failed", attempts: ExecuteSearchJob::MAX_ATTEMPTS)
    expect(adapter.delays.size).to eq(ExecuteSearchJob::MAX_ATTEMPTS - 1)
  end
end
