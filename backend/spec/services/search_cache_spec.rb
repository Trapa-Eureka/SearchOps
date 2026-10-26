require "rails_helper"

RSpec.describe SearchCache do
  let(:keyword) { create(:keyword, target_domain: "example.com") }
  let(:fingerprint) { "fp-1" }

  def cached_run(finished_at: 5.minutes.ago, keyword: self.keyword, fingerprint: self.fingerprint, target: "example.com", **attrs)
    run = create(:search_run, keyword: keyword, fingerprint: fingerprint, finished_at: finished_at, **attrs)
    create(:rank_snapshot, keyword: keyword, search_run: run, target_domain: target, captured_at: finished_at) if target
    run
  end

  describe ".ttl" do
    it "defaults to one hour", env: { "SEARCH_CACHE_TTL_SECONDS" => nil } do
      expect(described_class.ttl).to eq(3600)
    end

    it "reads the environment", env: { "SEARCH_CACHE_TTL_SECONDS" => "600" } do
      expect(described_class.ttl).to eq(600)
    end

    it "treats 0 as disabled", env: { "SEARCH_CACHE_TTL_SECONDS" => "0" } do
      expect(described_class.ttl).to eq(0)
    end

    it "falls back to the default for garbage instead of silently disabling the cache", env: { "SEARCH_CACHE_TTL_SECONDS" => "soon" } do
      expect(described_class.ttl).to eq(3600)
    end

    it "clamps negative and huge values", env: { "SEARCH_CACHE_TTL_SECONDS" => "-5" } do
      expect(described_class.ttl).to eq(0)
      ENV["SEARCH_CACHE_TTL_SECONDS"] = "99999999"
      expect(described_class.ttl).to eq(described_class::MAX_TTL_SECONDS)
    end
  end

  describe ".lookup", env: { "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
    it "returns a recent successful run for the same keyword and settings" do
      run = cached_run

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to eq(run)
    end

    it "returns the newest one" do
      cached_run(finished_at: 40.minutes.ago)
      newest = cached_run(finished_at: 10.minutes.ago)

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to eq(newest)
    end

    it "misses when the entry is older than the TTL" do
      cached_run(finished_at: 61.minutes.ago)

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to be_nil
    end

    it "hits right up to the TTL boundary" do
      run = cached_run(finished_at: 59.minutes.ago)

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to eq(run)
    end

    it "misses for failed, queued, or running runs" do
      cached_run(status: "failed", error_category: "upstream")
      create(:search_run, :queued, keyword: keyword, fingerprint: fingerprint)

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to be_nil
    end

    it "misses for different search settings" do
      cached_run(fingerprint: "other")

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to be_nil
    end

    it "does not share entries between keywords" do
      cached_run(keyword: create(:keyword, target_domain: "example.com"))

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to be_nil
    end

    it "never uses a cache hit as the source of another hit" do
      source = cached_run(finished_at: 50.minutes.ago)
      create(:search_run, :cache_hit, keyword: keyword, fingerprint: fingerprint, source_run: source, finished_at: 1.minute.ago)

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to eq(source)
    end

    it "misses when the cached snapshot is for a different target domain" do
      cached_run(target: "old-target.com")

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to be_nil
    end

    it "misses when the keyword now has a target but the cached run has no snapshot" do
      cached_run(target: nil)

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to be_nil
    end

    it "hits for a keyword without a target domain" do
      keyword.update!(target_domain: nil)
      run = cached_run(target: nil)

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to eq(run)
    end

    it "is disabled by a TTL of 0", env: { "SEARCH_CACHE_TTL_SECONDS" => "0" } do
      cached_run

      expect(described_class.lookup(keyword: keyword, fingerprint: fingerprint)).to be_nil
    end
  end
end
