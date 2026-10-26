require "rails_helper"

RSpec.describe KeywordFreshness do
  let(:keyword) { create(:keyword) }

  def info(kw = keyword)
    described_class.for(kw)[kw.id]
  end

  it "is no_data before any successful search" do
    expect(info).to have_attributes(state: "no_data", reason: nil, last_success_at: nil, last_attempt_status: nil)
  end

  it "is no_data (not stale) when the only attempt failed, but reports the failed attempt" do
    create(:search_run, :failed, keyword: keyword)

    expect(info).to have_attributes(state: "no_data", last_attempt_status: "failed")
  end

  it "is fresh after a recent success" do
    run = create(:search_run, keyword: keyword, finished_at: 1.hour.ago)

    expect(info).to have_attributes(state: "fresh", reason: nil, last_attempt_status: "succeeded")
    expect(info.last_success_at).to be_within(1.second).of(run.finished_at)
  end

  it "is stale, keeping the last good time, when the newest attempt failed" do
    good = create(:search_run, keyword: keyword, finished_at: 3.hours.ago)
    create(:search_run, :failed, keyword: keyword, finished_at: 1.hour.ago)

    result = info
    expect(result).to have_attributes(state: "stale", reason: "last_attempt_failed", last_attempt_status: "failed")
    expect(result.last_success_at).to be_within(1.second).of(good.finished_at)
    expect(result.stale?).to be(true)
  end

  it "is fresh again once a later attempt succeeds" do
    create(:search_run, :failed, keyword: keyword, finished_at: 3.hours.ago)
    create(:search_run, keyword: keyword, finished_at: 1.hour.ago)

    expect(info.state).to eq("fresh")
  end

  it "ignores attempts that are still queued or running" do
    create(:search_run, keyword: keyword, finished_at: 2.hours.ago)
    create(:search_run, :queued, keyword: keyword)
    create(:search_run, :running, keyword: keyword)

    expect(info.state).to eq("fresh")
  end

  it "ignores cache hits, which carry no new data" do
    keyword.update!(schedule: "daily")
    old_success = create(:search_run, keyword: keyword, finished_at: 40.hours.ago)
    create(:search_run, :cache_hit, keyword: keyword, finished_at: 1.minute.ago, source_run: old_success)

    expect(info).to have_attributes(state: "stale", reason: "overdue")
  end

  describe "overdue data" do
    it "marks a daily keyword stale after 1.5 days" do
      keyword.update!(schedule: "daily")
      create(:search_run, keyword: keyword, finished_at: 35.hours.ago)
      expect(info.state).to eq("fresh")

      create(:search_run, keyword: create(:keyword, schedule: "daily"), finished_at: 37.hours.ago)
      other = Keyword.where(schedule: "daily").where.not(id: keyword.id).first
      expect(info(other)).to have_attributes(state: "stale", reason: "overdue")
    end

    it "marks a weekly keyword stale after 10.5 days" do
      keyword.update!(schedule: "weekly")
      create(:search_run, keyword: keyword, finished_at: 10.days.ago)
      expect(info.state).to eq("fresh")

      create(:search_run, keyword: create(:keyword, schedule: "weekly"), finished_at: 11.days.ago)
      other = Keyword.where(schedule: "weekly").where.not(id: keyword.id).first
      expect(info(other).reason).to eq("overdue")
    end

    it "never marks a manual keyword overdue" do
      create(:search_run, keyword: keyword, finished_at: 90.days.ago)

      expect(info.state).to eq("fresh")
    end
  end

  it "answers many keywords with a fixed number of queries" do
    keywords = create_list(:keyword, 5)
    keywords.each { |kw| create(:search_run, keyword: kw) }

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      expect(described_class.for(keywords).size).to eq(5)
    end

    expect(queries.size).to eq(2)
  end

  it "returns an empty hash for no keywords" do
    expect(described_class.for([])).to eq({})
  end
end
