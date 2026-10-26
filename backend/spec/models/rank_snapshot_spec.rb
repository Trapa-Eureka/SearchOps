require "rails_helper"

RSpec.describe RankSnapshot, type: :model do
  it "has a valid factory" do
    expect(build(:rank_snapshot)).to be_valid
  end

  describe "rank" do
    it "may be nil when the domain was not found, and then is not 'found'" do
      snapshot = build(:rank_snapshot, rank: nil)

      expect(snapshot).to be_valid
      expect(snapshot.found?).to be(false)
    end

    it "is never zero or negative" do
      expect(build(:rank_snapshot, rank: 0)).not_to be_valid
      expect(build(:rank_snapshot, rank: -1)).not_to be_valid
    end

    it "is found at position 1" do
      snapshot = build(:rank_snapshot, rank: 1)

      expect(snapshot).to be_valid
      expect(snapshot.found?).to be(true)
    end

    it "rejects zero at the database level too" do
      expect { build(:rank_snapshot, rank: 0).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /rank_snapshots_rank_positive/)
    end
  end

  it "requires target domain and capture time" do
    snapshot = build(:rank_snapshot, target_domain: nil, captured_at: nil)

    expect(snapshot).not_to be_valid
    expect(snapshot.errors.attribute_names).to include(:target_domain, :captured_at)
  end

  it "allows only one snapshot per run" do
    existing = create(:rank_snapshot)
    duplicate = build(:rank_snapshot, keyword: existing.keyword, search_run: existing.search_run)

    expect(duplicate).not_to be_valid
  end

  it "requires the run to belong to the same keyword" do
    other_run = create(:search_run)
    snapshot = build(:rank_snapshot, keyword: create(:keyword), search_run: other_run)

    expect(snapshot).not_to be_valid
    expect(snapshot.errors[:search_run]).to include("must belong to the same keyword")
  end
end
