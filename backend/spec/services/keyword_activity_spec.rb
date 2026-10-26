require "rails_helper"

RSpec.describe KeywordActivity do
  let(:keyword) { create(:keyword, target_domain: "example.com") }

  def run(kw = keyword, *traits, **attrs)
    create(:search_run, *traits, keyword: kw, **attrs)
  end

  def snapshot(kw, rank, at: Time.current, fingerprint: "same")
    search_run = create(:search_run, keyword: kw, fingerprint: fingerprint)
    create(:rank_snapshot, keyword: kw, search_run: search_run, rank: rank, target_domain: "example.com", captured_at: at)
  end

  it "returns nothing for no keywords" do
    expect(described_class.for([])).to eq({})
  end

  it "gives a keyword without any run an empty strip and no rank" do
    info = described_class.for(keyword)[keyword.id]

    expect(info.recent_runs).to eq([])
    expect(info.latency_ms).to eq(samples: 0, p95: nil, max: nil)
    expect(info.rank).to be_nil
  end

  describe "recent runs" do
    it "lists runs oldest first with what a strip needs and nothing sensitive" do
      first = run(keyword, created_at: 3.hours.ago, upstream_latency_ms: 300)
      failed = run(keyword, :failed, created_at: 2.hours.ago, error_category: "timeout", attempts: 3, upstream_latency_ms: 15_000)
      hit = run(keyword, :cache_hit, created_at: 1.hour.ago)

      list = described_class.for(keyword)[keyword.id].recent_runs.select { |item| [ first.id, failed.id, hit.id ].include?(item[:id]) }

      expect(list.map { |item| item[:id] }).to eq([ first.id, failed.id, hit.id ])
      expect(list[1]).to include(status: "failed", error_category: "timeout", retried: true, latency_ms: 15_000, cache_hit: false)
      expect(list[2]).to include(cache_hit: true, retried: false)
      expect(list.flat_map(&:keys).uniq).to contain_exactly(:id, :status, :cache_hit, :error_category, :latency_ms, :retried, :created_at)
    end

    it "keeps only the newest RECENT_RUNS runs per keyword" do
      (described_class::RECENT_RUNS + 5).times { |index| run(keyword, created_at: (100 - index).minutes.ago) }
      other = create(:keyword)
      run(other)

      result = described_class.for([ keyword, other ])

      expect(result[keyword.id].recent_runs.size).to eq(described_class::RECENT_RUNS)
      expect(result[keyword.id].recent_runs.last[:created_at]).to be > result[keyword.id].recent_runs.first[:created_at]
      expect(result[other.id].recent_runs.size).to eq(1)
    end

    it "computes latency from runs that called SerpApi only, ignoring cache hits and missing values" do
      [ 100, 200, 300, 400 ].each { |ms| run(keyword, upstream_latency_ms: ms) }
      run(keyword, :queued)
      run(keyword, :cache_hit, upstream_latency_ms: 9_999)

      expect(described_class.for(keyword)[keyword.id].latency_ms).to eq(samples: 4, p95: 385, max: 400)
    end

    it "does not mix up two keywords" do
      other = create(:keyword)
      mine = run(keyword)
      theirs = run(other)

      result = described_class.for([ keyword, other ])

      expect(result[keyword.id].recent_runs.map { |item| item[:id] }).to eq([ mine.id ])
      expect(result[other.id].recent_runs.map { |item| item[:id] }).to eq([ theirs.id ])
    end
  end

  describe "rank" do
    it "is the newest snapshot, compared with the one before it (smaller is better)" do
      snapshot(keyword, 8, at: 2.days.ago)
      snapshot(keyword, 3, at: 1.day.ago)

      rank = described_class.for(keyword)[keyword.id].rank

      expect(rank).to include(rank: 3, found: true, target_domain: "example.com")
      expect(rank[:comparison]).to eq(status: "improved", delta: 5, previous_rank: 8)
    end

    it "reports not found as null, never zero, and a drop out of the window as dropped" do
      snapshot(keyword, 4, at: 2.days.ago)
      snapshot(keyword, nil, at: 1.day.ago)

      rank = described_class.for(keyword)[keyword.id].rank

      expect(rank).to include(rank: nil, found: false)
      expect(rank[:comparison]).to include(status: "dropped", previous_rank: 4)
    end

    it "calls the first snapshot a baseline" do
      snapshot(keyword, 6)

      expect(described_class.for(keyword)[keyword.id].rank[:comparison]).to include(status: "baseline", delta: nil)
    end

    it "does not compare snapshots from different search settings" do
      snapshot(keyword, 8, at: 2.days.ago, fingerprint: "a")
      snapshot(keyword, 3, at: 1.day.ago, fingerprint: "b")

      expect(described_class.for(keyword)[keyword.id].rank[:comparison]).to include(status: "not_comparable", delta: nil)
    end

    it "uses only the newest two snapshots of each keyword" do
      other = create(:keyword, target_domain: "example.com")
      snapshot(keyword, 9, at: 3.days.ago)
      snapshot(keyword, 7, at: 2.days.ago)
      snapshot(keyword, 5, at: 1.day.ago)
      snapshot(other, 2)

      result = described_class.for([ keyword, other ])

      expect(result[keyword.id].rank[:comparison]).to include(previous_rank: 7, status: "improved", delta: 2)
      expect(result[other.id].rank[:comparison][:status]).to eq("baseline")
    end
  end

  it "needs a fixed number of queries however many keywords there are" do
    keywords = create_list(:keyword, 6, target_domain: "example.com")
    keywords.each { |kw| run(kw); snapshot(kw, 3) }

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { described_class.for(keywords) }

    expect(queries.size).to be <= 4
  end
end
