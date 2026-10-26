require "rails_helper"

RSpec.describe SearchRun, type: :model do
  it "has a valid factory" do
    expect(build(:search_run)).to be_valid
  end

  it "requires a keyword and a fingerprint" do
    run = described_class.new
    expect(run).not_to be_valid
    expect(run.errors.attribute_names).to include(:keyword, :fingerprint)
  end

  it "defaults to queued status and no cache source" do
    run = described_class.new
    expect([ run.status, run.cache_source ]).to eq(%w[queued none])
    expect(run.request_metadata).to eq({})
  end

  it "validates status, cache source, and error category against allow-lists" do
    run = build(:search_run, status: "done", cache_source: "cdn", error_category: "boom")
    expect(run).not_to be_valid
    expect(run.errors.attribute_names).to include(:status, :cache_source, :error_category)
  end

  it "accepts every documented error category" do
    SearchRun::ERROR_CATEGORIES.each do |category|
      expect(build(:search_run, status: "failed", error_category: category)).to be_valid
    end
  end

  it "rejects negative latency and out-of-range HTTP status" do
    expect(build(:search_run, upstream_latency_ms: -1)).not_to be_valid
    expect(build(:search_run, http_status: 99)).not_to be_valid
    expect(build(:search_run, http_status: 600)).not_to be_valid
    expect(build(:search_run, upstream_latency_ms: 0, http_status: 200)).to be_valid
  end

  it "deletes its results and snapshot with it" do
    snapshot = create(:rank_snapshot)
    run = snapshot.search_run
    create(:search_result, search_run: run, position: 1)

    expect { run.destroy! }
      .to change(SearchResult, :count).by(-1)
      .and change(RankSnapshot, :count).by(-1)
  end
end
