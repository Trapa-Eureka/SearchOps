require "rails_helper"

RSpec.describe RankComparison do
  describe ".call" do
    {
      [ 5, 2 ] => [ "improved", 3 ],
      [ 2, 5 ] => [ "declined", -3 ],
      [ 4, 4 ] => [ "unchanged", 0 ],
      [ 1, 2 ] => [ "declined", -1 ],
      [ nil, 3 ] => [ "entered", nil ],
      [ 3, nil ] => [ "dropped", nil ],
      [ nil, nil ] => [ "not_found", nil ]
    }.each do |(previous, current), (status, delta)|
      it "previous=#{previous.inspect} current=#{current.inspect} is #{status}" do
        result = described_class.call(previous: previous, current: current)

        expect(result.status).to eq(status)
        expect(result.delta).to eq(delta)
        expect(result.previous_rank).to eq(previous)
        expect(result.current_rank).to eq(current)
      end
    end

    it "treats a smaller number as a better position" do
      expect(described_class.call(previous: 10, current: 1).status).to eq("improved")
    end
  end

  describe ".between" do
    let(:keyword) { create(:keyword, target_domain: "example.com") }

    def snapshot(rank:, fingerprint: "fp-1", target: "example.com")
      run = create(:search_run, keyword: keyword, fingerprint: fingerprint)
      create(:rank_snapshot, keyword: keyword, search_run: run, rank: rank, target_domain: target)
    end

    it "is a baseline when there is no previous snapshot" do
      result = described_class.between(previous: nil, current: snapshot(rank: 4))

      expect(result.status).to eq("baseline")
      expect(result.current_rank).to eq(4)
    end

    it "compares snapshots from equivalent searches" do
      result = described_class.between(previous: snapshot(rank: 6), current: snapshot(rank: 3))

      expect(result.status).to eq("improved")
      expect(result.delta).to eq(3)
    end

    it "refuses to compare snapshots with different search settings" do
      result = described_class.between(
        previous: snapshot(rank: 6, fingerprint: "fp-1"),
        current: snapshot(rank: 3, fingerprint: "fp-2")
      )

      expect(result.status).to eq("not_comparable")
      expect(result.delta).to be_nil
    end

    it "refuses to compare snapshots for different target domains" do
      result = described_class.between(
        previous: snapshot(rank: 6, target: "example.com"),
        current: snapshot(rank: 3, target: "other.org")
      )

      expect(result.status).to eq("not_comparable")
    end
  end
end
