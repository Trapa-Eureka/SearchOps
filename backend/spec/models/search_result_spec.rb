require "rails_helper"

RSpec.describe SearchResult, type: :model do
  it "has a valid factory" do
    expect(build(:search_result)).to be_valid
  end

  it "requires a position of 1 or more" do
    expect(build(:search_result, position: 0)).not_to be_valid
    expect(build(:search_result, position: -2)).not_to be_valid
    expect(build(:search_result, position: nil)).not_to be_valid
    expect(build(:search_result, position: 1)).to be_valid
  end

  it "keeps a position unique within a run but not across runs" do
    run = create(:search_run)
    create(:search_result, search_run: run, position: 1)

    expect(build(:search_result, search_run: run, position: 1)).not_to be_valid
    expect(build(:search_result, position: 1)).to be_valid
  end

  it "enforces unique positions in the database as well" do
    run = create(:search_run)
    create(:search_result, search_run: run, position: 1)

    expect { build(:search_result, search_run: run, position: 1).save!(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "url" do
    it "must be present" do
      expect(build(:search_result, url: nil)).not_to be_valid
    end

    [ "javascript:alert(1)", "ftp://example.com/file", "not a url", "/relative/path" ].each do |bad|
      it "rejects #{bad.inspect}" do
        expect(build(:search_result, url: bad)).not_to be_valid
      end
    end

    it "accepts http and https" do
      expect(build(:search_result, url: "http://example.com/a?b=1")).to be_valid
      expect(build(:search_result, url: "https://example.com/a")).to be_valid
    end
  end

  it "limits the size of the extra metadata" do
    result = build(:search_result, extra: { "blob" => "x" * (SearchResult::EXTRA_MAX_BYTES + 1) })
    expect(result).not_to be_valid
    expect(result.errors[:extra].join).to include("too large")
  end

  it "limits title and snippet length" do
    expect(build(:search_result, title: "t" * (SearchResult::TITLE_MAX_LENGTH + 1))).not_to be_valid
    expect(build(:search_result, snippet: "s" * (SearchResult::SNIPPET_MAX_LENGTH + 1))).not_to be_valid
  end
end
