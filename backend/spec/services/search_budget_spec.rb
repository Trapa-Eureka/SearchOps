require "rails_helper"

RSpec.describe SearchBudget do
  around do |example|
    original = ENV["SEARCH_MAX_REQUESTS_PER_DAY"]
    example.run
  ensure
    original.nil? ? ENV.delete("SEARCH_MAX_REQUESTS_PER_DAY") : ENV["SEARCH_MAX_REQUESTS_PER_DAY"] = original
  end

  def limit!(value)
    ENV["SEARCH_MAX_REQUESTS_PER_DAY"] = value
  end

  describe ".daily_limit" do
    it "defaults to 5" do
      ENV.delete("SEARCH_MAX_REQUESTS_PER_DAY")
      expect(described_class.daily_limit).to eq(5)
    end

    it "reads the environment" do
      limit!("12")
      expect(described_class.daily_limit).to eq(12)
    end

    it "fails closed on garbage" do
      limit!("lots")
      expect(described_class.daily_limit).to eq(0)
    end
  end

  describe ".check!" do
    it "allows searches below the limit" do
      limit!("2")
      create(:search_run)

      expect { described_class.check! }.not_to raise_error
    end

    it "raises once the limit is reached and reports usage" do
      limit!("2")
      create_list(:search_run, 2)

      expect { described_class.check! }.to raise_error(SearchBudget::Exceeded) do |error|
        expect(error.limit).to eq(2)
        expect(error.used).to eq(2)
      end
    end

    it "does not count runs from previous days" do
      limit!("1")
      create(:search_run, created_at: 2.days.ago)

      expect { described_class.check! }.not_to raise_error
    end

    it "blocks everything when the limit is zero" do
      limit!("0")

      expect { described_class.check! }.to raise_error(SearchBudget::Exceeded)
    end
  end
end
