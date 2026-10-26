require "rails_helper"

RSpec.describe SearchOpsBenchmark::DatabaseGuard do
  it "refuses a database that is not a dedicated scratch database, and says which one" do
    expect { described_class.check! }.to raise_error(described_class::Refused, /searchops_test.*must end in _bench/m)
  end

  it "refuses the real development database name" do
    allow(ActiveRecord::Base.connection).to receive(:current_database).and_return("searchops_development")

    expect { described_class.check! }.to raise_error(described_class::Refused, /searchops_development/)
  end

  it "accepts an allowed suffix and returns the name" do
    expect(described_class.check!(allowed_suffixes: %w[_test])).to eq("searchops_test")
  end

  it "wipes keywords, runs, results, snapshots, and intent requests" do
    snapshot = create(:rank_snapshot)
    create(:search_result, search_run: snapshot.search_run)
    create(:intent_request)

    described_class.wipe!

    expect([ Keyword, SearchRun, SearchResult, RankSnapshot, IntentRequest ].map(&:count)).to eq([ 0, 0, 0, 0, 0 ])
  end
end
