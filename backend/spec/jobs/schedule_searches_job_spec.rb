require "rails_helper"

RSpec.describe ScheduleSearchesJob, env: { "SERPAPI_API_KEY" => "schedule-spec-key-1234", "SEARCH_MAX_REQUESTS_PER_DAY" => "50", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
  def enqueued_run_ids
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job["job_class"] == "ExecuteSearchJob" }.map { |job| job["arguments"].first }
  end

  it "enqueues scheduled searches for due keywords only" do
    daily = create(:keyword, schedule: "daily")
    weekly = create(:keyword, schedule: "weekly")
    create(:keyword, schedule: "manual")
    create(:keyword, schedule: "daily", active: false)

    described_class.perform_now

    runs = SearchRun.all
    expect(runs.map(&:keyword_id)).to contain_exactly(daily.id, weekly.id)
    expect(runs.map(&:triggered_by).uniq).to eq([ "scheduled" ])
    expect(runs.map(&:status).uniq).to eq([ "queued" ])
    expect(enqueued_run_ids).to match_array(runs.map(&:id))
  end

  it "skips keywords that were searched within their interval" do
    keyword = create(:keyword, schedule: "daily")
    create(:search_run, keyword: keyword, created_at: 2.hours.ago)

    described_class.perform_now

    expect(SearchRun.where(triggered_by: "scheduled")).to be_empty
  end

  it "searches again once the interval has passed" do
    keyword = create(:keyword, schedule: "daily")
    create(:search_run, keyword: keyword, created_at: 25.hours.ago)

    described_class.perform_now

    expect(keyword.search_runs.where(triggered_by: "scheduled").count).to eq(1)
  end

  it "is harmless when the tick fires twice" do
    create(:keyword, schedule: "daily")

    2.times { described_class.perform_now }

    expect(SearchRun.count).to eq(1)
    expect(enqueued_run_ids.size).to eq(1)
  end

  it "reuses a fresh result instead of calling SerpApi again" do
    keyword = create(:keyword, schedule: "weekly", target_domain: nil)
    fingerprint = SearchFingerprint.call(SearchProvider::Request.from_keyword(keyword))
    create(:search_run, keyword: keyword, fingerprint: fingerprint, created_at: 8.days.ago, finished_at: 5.minutes.ago)

    described_class.perform_now

    scheduled = keyword.search_runs.find_by(triggered_by: "scheduled")
    expect(scheduled).to have_attributes(cache_source: "app", status: "succeeded", upstream_calls: 0)
    expect(enqueued_run_ids).to be_empty
  end

  it "stops for the day once the budget is exhausted without creating failed runs", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "2" } do
    create_list(:keyword, 4, schedule: "daily")

    described_class.perform_now

    expect(SearchRun.count).to eq(2)
    expect(SearchRun.pluck(:status).uniq).to eq([ "queued" ])
  end

  it "does nothing when SerpApi is not configured", env: { "SERPAPI_API_KEY" => "replace_me" } do
    create(:keyword, schedule: "daily")

    expect { described_class.perform_now }.not_to change(SearchRun, :count)
  end

  it "never involves Laya or the network" do
    create(:keyword, schedule: "daily")

    described_class.perform_now

    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it "logs a one-line summary without search terms" do
    create(:keyword, query: "secret search words", schedule: "daily")
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with(a_string_matching(/schedule_tick due=1 enqueued=1/))
    expect(Rails.logger).not_to have_received(:info).with(a_string_including("secret search words"))
  end
end
