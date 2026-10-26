require "rails_helper"

RSpec.describe Intent::PlanValidator do
  def validate(plan)
    described_class.call(plan)
  end

  let(:rank_plan) do
    { "intent" => "organic_rank_tracking", "query" => "react developer", "country" => "ph", "language" => "en",
      "target_domain" => "https://www.Example.com/jobs" }
  end

  describe "a complete plan" do
    it "is valid and normalized" do
      result = validate(rank_plan)

      expect(result.valid?).to be(true)
      expect(result.plan).to eq(
        "intent" => "organic_rank_tracking", "engine" => "google", "query" => "react developer", "country" => "ph",
        "language" => "en", "target_domain" => "example.com", "compare_previous" => false, "only_new" => false
      )
    end

    it "accepts symbol keys" do
      expect(validate(rank_plan.symbolize_keys).valid?).to be(true)
    end

    it "squishes the query and lowercases codes" do
      result = validate(rank_plan.merge("query" => "  react   developer ", "country" => " PH ", "language" => "EN"))

      expect(result.plan).to include("query" => "react developer", "country" => "ph", "language" => "en")
    end

    it "derives the engine from the intent" do
      expect(validate(rank_plan).plan["engine"]).to eq("google")
      expect(validate(rank_plan.merge("intent" => "job_search")).plan["engine"]).to eq("google_jobs")
    end

    it "keeps real booleans for the flags" do
      result = validate(rank_plan.merge("compare_previous" => true, "only_new" => true))

      expect(result.plan).to include("compare_previous" => true, "only_new" => true)
    end
  end

  describe "required fields" do
    it "lists what an organic rank check still needs" do
      result = validate("intent" => "organic_rank_tracking")

      expect(result.valid?).to be(false)
      expect(result.errors).to eq({})
      expect(result.missing).to eq(%w[query country language target_domain])
    end

    it "does not need a target domain for a job search" do
      expect(validate("intent" => "job_search", "query" => "x", "country" => "ph", "language" => "en").valid?).to be(true)
    end

    it "needs nothing for a history request" do
      expect(validate("intent" => "search_history").valid?).to be(true)
    end

    it "treats blank strings as missing" do
      result = validate(rank_plan.merge("query" => "   ", "target_domain" => ""))

      expect(result.missing).to contain_exactly("query", "target_domain")
    end

    it "does not report a field as missing when it is present but invalid" do
      result = validate(rank_plan.merge("country" => "zz"))

      expect(result.errors).to eq("country" => "not_allowed")
      expect(result.missing).to eq([])
    end
  end

  describe "intents" do
    it "accepts only the known intents" do
      %w[delete_keywords drop_table export_keys shopping_price_watch].each do |intent|
        result = validate("intent" => intent)

        expect(result.errors).to eq("intent" => "not_allowed")
        expect(result.plan).to eq({})
      end
    end

    it "rejects a missing or non-string intent" do
      [ {}, { "intent" => nil }, { "intent" => 5 }, { "intent" => [ "job_search" ] }, { "intent" => { "a" => 1 } } ].each do |plan|
        expect(validate(plan).errors).to have_key("intent")
      end
    end

    it "reduces unsupported to an empty plan" do
      result = validate("intent" => "unsupported", "query" => "ignored")

      expect(result.plan).to eq("intent" => "unsupported")
      expect(result.valid?).to be(true)
    end

    it "rejects a plan that is not an object" do
      [ nil, "text", 5, [ 1 ] ].each do |input|
        expect(validate(input).errors).to eq("plan" => "must_be_an_object")
      end
    end
  end

  describe "unknown fields" do
    it "are rejected, not ignored" do
      result = validate(rank_plan.merge("sql" => "DROP TABLE keywords", "run_as" => "admin", "url" => "http://evil.test"))

      expect(result.errors).to include("sql" => "unknown_field", "run_as" => "unknown_field", "url" => "unknown_field")
      expect(result.valid?).to be(false)
    end

    it "cannot name a different engine" do
      expect(validate(rank_plan.merge("engine" => "bing")).errors).to eq("engine" => "does_not_match_intent")
      expect(validate(rank_plan.merge("engine" => "google_jobs")).errors).to eq("engine" => "does_not_match_intent")
    end

    it "accepts the matching engine" do
      expect(validate(rank_plan.merge("engine" => "google")).valid?).to be(true)
    end
  end

  describe "values" do
    it "rejects countries and languages outside the allow-lists" do
      result = validate(rank_plan.merge("country" => "xx", "language" => "klingon"))

      expect(result.errors).to eq("country" => "not_allowed", "language" => "not_allowed")
    end

    it "rejects non-string values for text fields" do
      result = validate(rank_plan.merge("query" => 5, "country" => [ "ph" ], "target_domain" => { "a" => 1 }))

      expect(result.errors).to eq("query" => "must_be_text", "country" => "must_be_text", "target_domain" => "must_be_text")
    end

    it "rejects an over-long query and control characters" do
      expect(validate(rank_plan.merge("query" => "a" * 201)).errors).to eq("query" => "too_long")
      expect(validate(rank_plan.merge("query" => "a\u0000b")).errors).to eq("query" => "has_control_characters")
      expect(validate(rank_plan.merge("location" => "Man\u0000ila")).errors).to eq("location" => "has_control_characters")
    end

    it "rejects domains that are not safe hostnames" do
      [ "localhost", "10.0.0.1", "ftp://example.com", "user@example.com", "not a domain", "javascript:alert(1)" ].each do |bad|
        expect(validate(rank_plan.merge("target_domain" => bad)).errors).to eq("target_domain" => "not_a_domain")
      end
    end

    it "rejects flags that are not real booleans" do
      [ "true", "false", 1, 0, "yes", [] ].each do |bad|
        expect(validate(rank_plan.merge("compare_previous" => bad)).errors).to eq("compare_previous" => "must_be_true_or_false")
      end
    end

    it "treats null flags as off" do
      expect(validate(rank_plan.merge("compare_previous" => nil)).plan["compare_previous"]).to be(false)
    end

    it "checks that a keyword id exists and is an integer" do
      keyword = create(:keyword)

      expect(validate("intent" => "search_history", "keyword_id" => keyword.id).plan["keyword_id"]).to eq(keyword.id)
      expect(validate("intent" => "search_history", "keyword_id" => 0).errors).to eq("keyword_id" => "not_found")
      expect(validate("intent" => "search_history", "keyword_id" => "1").errors).to eq("keyword_id" => "must_be_an_integer")
      expect(validate("intent" => "search_history", "keyword_id" => 1.5).errors).to eq("keyword_id" => "must_be_an_integer")
    end
  end

  it "cannot express any destructive action: the field set is closed" do
    expect(Intent::Catalog::PLAN_FIELDS).to match_array(
      %w[query country language location target_domain compare_previous only_new intent engine keyword_id]
    )
    expect(Intent::Catalog::INTENTS).to eq(%w[organic_rank_tracking job_search search_history unsupported])
  end

  describe "the location" do
    it "is optional, and blank means none" do
      [ nil, "", "   " ].each { |value| expect(validate(rank_plan.merge("location" => value)).plan).not_to have_key("location") }
    end

    it "is squished" do
      expect(validate(rank_plan.merge("location" => "  Metro \n  Manila ")).plan["location"]).to eq("Metro Manila")
    end

    it "must be text, not a number, list, or object" do
      [ 12, [ "Manila" ], { "city" => "Manila" }, true ].each do |value|
        expect(validate(rank_plan.merge("location" => value)).errors).to eq("location" => "must_be_text")
      end
    end

    it "has a length limit" do
      ok = validate(rank_plan.merge("location" => "a" * Keyword::LOCATION_MAX_LENGTH))
      too_long = validate(rank_plan.merge("location" => "a" * (Keyword::LOCATION_MAX_LENGTH + 1)))

      expect(ok.errors).to eq({})
      expect(too_long.errors).to eq("location" => "too_long")
    end

    it "cannot carry control characters" do
      [ "Man\u0000ila", "Man\u0007ila", "Manila\u001b[31m" ].each do |value|
        expect(validate(rank_plan.merge("location" => value)).errors).to eq("location" => "has_control_characters")
      end
    end
  end
end
