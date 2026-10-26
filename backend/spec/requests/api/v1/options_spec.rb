require "rails_helper"

RSpec.describe "Api::V1::Options", type: :request do
  def json
    response.parsed_body
  end

  it "returns the allowed values straight from the models" do
    get "/api/v1/options"

    expect(response).to have_http_status(:ok)
    data = json["data"]
    expect(data["engines"]).to eq(Keyword::ENGINES)
    expect(data["countries"]).to eq(Keyword::COUNTRIES)
    expect(data["languages"]).to eq(Keyword::LANGUAGES)
    expect(data["schedules"]).to eq(%w[manual daily weekly])
  end

  it "includes the limits that the keyword and planner forms must respect", env: { "SEARCH_MAX_KEYWORDS" => "12" } do
    get "/api/v1/options"

    expect(json["data"]["limits"]).to eq(
      "query_max_length" => 200, "location_max_length" => 100, "max_keywords" => 12,
      "intent_text_max_length" => 500, "max_per_page" => 100
    )
  end

  it "says whether natural-language planning is switched on" do
    ENV["LAYA_ENABLED"] = "true"
    get "/api/v1/options"
    expect(json["data"]["features"]).to eq("intent_planning" => true)

    ENV["LAYA_ENABLED"] = "false"
    get "/api/v1/options"
    expect(json["data"]["features"]).to eq("intent_planning" => false)
  ensure
    ENV.delete("LAYA_ENABLED")
  end

  it "makes no outbound request and exposes no secret" do
    get "/api/v1/options"

    expect(a_request(:any, /.*/)).not_to have_been_made
    expect(response.body).not_to match(/api[_-]?key|secret|password/i)
  end

  it "only offers values the keyword API accepts" do
    get "/api/v1/options"
    data = json["data"]

    data["countries"].each do |country|
      expect(build(:keyword, country: country, language: "en")).to be_valid
    end
    data["languages"].each do |language|
      expect(build(:keyword, country: "us", language: language)).to be_valid
    end
  end
end
