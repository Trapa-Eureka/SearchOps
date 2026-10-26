require "rails_helper"

RSpec.describe Keyword, type: :model do
  subject(:keyword) { build(:keyword) }

  it "has a valid factory" do
    expect(keyword).to be_valid
  end

  describe "defaults" do
    it "is active, manual, and uses the google engine" do
      record = described_class.new

      expect(record.active).to be(true)
      expect(record.schedule).to eq("manual")
      expect(record.engine).to eq("google")
    end
  end

  describe "query" do
    it "is required" do
      keyword.query = "   "
      expect(keyword).not_to be_valid
      expect(keyword.errors[:query]).to include("can't be blank")
    end

    it "squishes surrounding and repeated whitespace" do
      keyword.query = "  senior   react \n developer  "
      keyword.validate
      expect(keyword.query).to eq("senior react developer")
    end

    it "accepts the maximum length and rejects one more character" do
      keyword.query = "a" * Keyword::QUERY_MAX_LENGTH
      expect(keyword).to be_valid

      keyword.query = "a" * (Keyword::QUERY_MAX_LENGTH + 1)
      expect(keyword).not_to be_valid
    end

    it "rejects control characters such as NUL" do
      keyword.query = "react\u0000developer"
      expect(keyword).not_to be_valid
      expect(keyword.errors[:query].join).to include("control characters")
    end

    it "accepts non-ASCII text" do
      keyword.query = "리액트 개발자 원격"
      expect(keyword).to be_valid
    end
  end

  describe "engine, country, language, schedule" do
    it "rejects an engine outside the allow-list" do
      keyword.engine = "bing"
      expect(keyword).not_to be_valid
    end

    it "rejects google_jobs until a provider supports it" do
      keyword.engine = "google_jobs"
      expect(keyword).not_to be_valid
    end

    it "downcases and accepts a known country and language" do
      keyword.country = " PH "
      keyword.language = "EN"
      expect(keyword).to be_valid
      expect([ keyword.country, keyword.language ]).to eq(%w[ph en])
    end

    it "rejects unknown or missing country and language" do
      keyword.country = "zz"
      keyword.language = "xx"
      expect(keyword).not_to be_valid
      expect(keyword.errors.attribute_names).to include(:country, :language)

      keyword.country = nil
      expect(keyword).not_to be_valid
    end

    it "accepts only the listed schedules" do
      Keyword::SCHEDULES.each do |schedule|
        keyword.schedule = schedule
        expect(keyword).to be_valid
      end

      keyword.schedule = "every_minute"
      expect(keyword).not_to be_valid
    end
  end

  describe "location" do
    it "is optional and blank becomes nil" do
      keyword.location = "   "
      expect(keyword).to be_valid
      expect(keyword.location).to be_nil
    end

    it "is limited in length" do
      keyword.location = "x" * (Keyword::LOCATION_MAX_LENGTH + 1)
      expect(keyword).not_to be_valid
    end

    it "rejects control characters without raising" do
      keyword.location = "Man\u0000ila"
      expect(keyword).not_to be_valid
    end
  end

  describe "target_domain" do
    it "is optional and blank becomes nil" do
      keyword.target_domain = ""
      expect(keyword).to be_valid
      expect(keyword.target_domain).to be_nil
    end

    it "is stored as a canonical hostname" do
      keyword.target_domain = "https://WWW.Example.com/some/path"
      expect(keyword).to be_valid
      expect(keyword.target_domain).to eq("example.com")
    end

    [ "localhost", "10.0.0.1", "ftp://example.com", "user@example.com", "not a domain", "exa\u0000mple.com" ].each do |bad|
      it "rejects #{bad.inspect}" do
        keyword.target_domain = bad
        expect(keyword).not_to be_valid
        expect(keyword.errors[:target_domain]).to include("is not a valid domain")
      end
    end
  end

  describe "uniqueness" do
    it "rejects the same query with identical search settings" do
      create(:keyword, query: "react", location: "Manila", target_domain: "example.com")
      duplicate = build(:keyword, query: "  React ".downcase, location: "Manila", target_domain: "example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:query].join).to include("already exists")
    end

    it "treats two keywords without a location as duplicates" do
      create(:keyword, query: "react")
      expect(build(:keyword, query: "react")).not_to be_valid
    end

    it "allows the same query with a different country, location, or target domain" do
      create(:keyword, query: "react")

      expect(build(:keyword, query: "react", country: "ph")).to be_valid
      expect(build(:keyword, query: "react", location: "Manila")).to be_valid
      expect(build(:keyword, query: "react", target_domain: "example.com")).to be_valid
    end

    it "is also enforced by the database" do
      create(:keyword, query: "react")

      expect { build(:keyword, query: "react").save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "keyword limit" do
    around do |example|
      original = ENV["SEARCH_MAX_KEYWORDS"]
      ENV["SEARCH_MAX_KEYWORDS"] = "2"
      example.run
    ensure
      ENV["SEARCH_MAX_KEYWORDS"] = original
    end

    it "rejects new keywords once the limit is reached" do
      create_list(:keyword, 2)

      fresh = build(:keyword)
      expect(fresh).not_to be_valid
      expect(fresh.errors[:base].join).to include("keyword limit reached (2)")
    end

    it "still allows updating existing keywords at the limit" do
      existing = create_list(:keyword, 2).first

      expect(existing.update(schedule: "daily")).to be(true)
    end
  end

  describe ".max_keywords" do
    it "defaults to 50" do
      original = ENV.delete("SEARCH_MAX_KEYWORDS")
      expect(described_class.max_keywords).to eq(50)
    ensure
      ENV["SEARCH_MAX_KEYWORDS"] = original if original
    end
  end

  describe ".active" do
    it "returns only active keywords" do
      active = create(:keyword, active: true)
      create(:keyword, active: false)

      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe "destroying a keyword" do
    it "removes its runs, results, and snapshots" do
      snapshot = create(:rank_snapshot)
      run = snapshot.search_run
      create(:search_result, search_run: run, position: 1)

      expect { snapshot.keyword.destroy! }
        .to change(SearchRun, :count).by(-1)
        .and change(SearchResult, :count).by(-1)
        .and change(RankSnapshot, :count).by(-1)
    end
  end
end
