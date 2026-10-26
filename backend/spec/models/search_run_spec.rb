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

  describe "execution tracking" do
    it "defaults to a manual trigger with zero attempts and upstream calls" do
      run = described_class.new

      expect([ run.triggered_by, run.attempts, run.upstream_calls ]).to eq([ "manual", 0, 0 ])
    end

    it "accepts only known triggers" do
      expect(build(:search_run, triggered_by: "scheduled")).to be_valid
      expect(build(:search_run, triggered_by: "robot")).not_to be_valid
    end

    it "rejects negative counters, in the model and in the database" do
      expect(build(:search_run, attempts: -1)).not_to be_valid
      expect(build(:search_run, upstream_calls: -1)).not_to be_valid
      expect { build(:search_run, upstream_calls: -1).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /search_runs_counters_non_negative/)
    end

    it "accepts the budget and abandoned categories" do
      expect(build(:search_run, :failed, error_category: "budget")).to be_valid
      expect(build(:search_run, :failed, error_category: "abandoned")).to be_valid
    end
  end

  describe "cache hits" do
    it "need a source run, and only cache hits may have one" do
      source = create(:search_run)

      expect(build(:search_run, cache_source: "app", source_run: nil)).not_to be_valid
      expect(build(:search_run, cache_source: "none", source_run: source)).not_to be_valid
      expect(build(:search_run, :cache_hit, source_run: source, keyword: source.keyword)).to be_valid
    end

    it "serve results from the source run" do
      hit = create(:search_run, :cache_hit)

      expect(hit.cache_hit?).to be(true)
      expect(hit.results_run).to eq(hit.source_run)
      expect(hit.source_run.results_run).to eq(hit.source_run)
    end

    it "survive the removal of the source run" do
      hit = create(:search_run, :cache_hit)
      hit.source_run.delete

      expect(hit.reload.source_run_id).to be_nil
    end
  end

  describe "scopes" do
    it "separates active, finished, and upstream runs" do
      queued = create(:search_run, :queued)
      running = create(:search_run, :running)
      done = create(:search_run)
      failed = create(:search_run, :failed)
      hit = create(:search_run, :cache_hit)

      expect(described_class.active).to contain_exactly(queued, running)
      expect(described_class.finished).to include(done, failed, hit)
      expect(described_class.finished).not_to include(queued, running)
      expect(described_class.upstream).not_to include(hit)
      expect(queued.active?).to be(true)
      expect(done.active?).to be(false)
    end
  end
end
