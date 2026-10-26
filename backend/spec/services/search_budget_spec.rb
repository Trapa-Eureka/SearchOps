require "rails_helper"

RSpec.describe SearchBudget do
  def limit!(value)
    ENV["SEARCH_MAX_REQUESTS_PER_DAY"] = value
  end

  describe ".daily_limit" do
    it "defaults to 5", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => nil } do
      expect(described_class.daily_limit).to eq(5)
    end

    it "reads the environment", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "12" } do
      expect(described_class.daily_limit).to eq(12)
    end

    it "fails closed on garbage", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "lots" } do
      expect(described_class.daily_limit).to eq(0)
    end
  end

  describe "usage", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "10" } do
    it "sums real upstream calls, including retries" do
      create(:search_run, upstream_calls: 3)
      create(:search_run, upstream_calls: 1)

      expect(described_class.used_today).to eq(4)
    end

    it "does not count cache hits" do
      create(:search_run, :cache_hit)

      expect(described_class.used_today).to eq(1) # only the cache hit's source run
    end

    it "reserves one call for each queued run that has not been tried yet" do
      create(:search_run, :queued)
      create(:search_run, :queued)

      expect(described_class.used_today).to eq(2)
    end

    it "does not reserve for a queued run that is waiting for a retry (its calls are already counted)" do
      create(:search_run, :queued, upstream_calls: 2)

      expect(described_class.used_today).to eq(2)
    end

    it "does not count runs that failed without sending anything" do
      create(:search_run, :failed, upstream_calls: 0, error_category: "budget")

      expect(described_class.used_today).to eq(0)
    end

    it "lets a run ignore its own reservation" do
      run = create(:search_run, :queued)

      expect(described_class.used_today).to eq(1)
      expect(described_class.used_today(exclude_run: run)).to eq(0)
    end

    it "ignores runs from previous days" do
      create(:search_run, upstream_calls: 4, created_at: 2.days.ago)

      expect(described_class.used_today).to eq(0)
    end
  end

  describe ".check!" do
    it "allows searches below the limit", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "2" } do
      create(:search_run, upstream_calls: 1)

      expect { described_class.check! }.not_to raise_error
    end

    it "raises once the limit is reached and reports usage", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "2" } do
      create(:search_run, upstream_calls: 2)

      expect { described_class.check! }.to raise_error(SearchBudget::Exceeded) do |error|
        expect(error.limit).to eq(2)
        expect(error.used).to eq(2)
      end
    end

    it "counts queued reservations so a burst of requests cannot overshoot", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "2" } do
      create_list(:search_run, 2, :queued)

      expect { described_class.check! }.to raise_error(SearchBudget::Exceeded)
    end

    it "blocks everything when the limit is zero", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "0" } do
      expect { described_class.check! }.to raise_error(SearchBudget::Exceeded)
    end
  end

  describe ".remaining", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "3" } do
    it "never goes below zero" do
      create(:search_run, upstream_calls: 5)

      expect(described_class.remaining).to eq(0)
    end

    it "is the limit minus usage" do
      create(:search_run, upstream_calls: 1)

      expect(described_class.remaining).to eq(2)
    end
  end
end
