require "rails_helper"

RSpec.describe ReapStuckRunsJob do
  def stale(run, age)
    run.update_columns(updated_at: age.ago)
    run
  end

  it "fails runs that have been running far too long" do
    run = stale(create(:search_run, :running, upstream_calls: 1), 11.minutes)

    described_class.perform_now

    expect(run.reload).to have_attributes(status: "failed", error_category: "abandoned")
    expect(run.finished_at).to be_present
    expect(run.request_metadata["error_message"]).to include("Worker stopped")
  end

  it "fails runs that were never picked up" do
    run = stale(create(:search_run, :queued), 31.minutes)

    described_class.perform_now

    expect(run.reload).to have_attributes(status: "failed", error_category: "abandoned")
  end

  it "leaves recent runs alone" do
    running = stale(create(:search_run, :running), 2.minutes)
    queued = stale(create(:search_run, :queued), 20.minutes)

    described_class.perform_now

    expect(running.reload.status).to eq("running")
    expect(queued.reload.status).to eq("queued")
  end

  it "leaves finished runs alone" do
    done = stale(create(:search_run), 3.days)
    failed = stale(create(:search_run, :failed), 3.days)

    described_class.perform_now

    expect(done.reload.status).to eq("succeeded")
    expect(failed.reload).to have_attributes(status: "failed", error_category: "upstream")
  end

  it "unblocks the keyword so it can be searched again" do
    keyword = create(:keyword)
    stuck = stale(create(:search_run, :running, keyword: keyword, fingerprint: "fp"), 15.minutes)

    expect { create(:search_run, :queued, keyword: keyword, fingerprint: "fp") }.to raise_error(ActiveRecord::RecordNotUnique)

    described_class.perform_now

    expect(stuck.reload.status).to eq("failed")
    expect { create(:search_run, :queued, keyword: keyword, fingerprint: "fp") }.not_to raise_error
  end

  it "keeps the previous successful data" do
    keyword = create(:keyword, target_domain: "example.com")
    good = create(:search_run, keyword: keyword)
    create(:rank_snapshot, keyword: keyword, search_run: good, rank: 3)
    stale(create(:search_run, :running, keyword: keyword, fingerprint: "other"), 20.minutes)

    described_class.perform_now

    expect(keyword.rank_snapshots.pluck(:rank)).to eq([ 3 ])
  end
end
