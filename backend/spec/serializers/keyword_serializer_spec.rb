require "rails_helper"

RSpec.describe KeywordSerializer do
  let(:keyword) { create(:keyword, target_domain: "example.com") }

  it "returns only the public fields when no freshness or activity is given" do
    data = described_class.call(keyword)

    expect(data.keys).to match_array(%w[id query engine country language location target_domain active schedule created_at updated_at])
  end

  it "adds freshness and activity when they are given, and nothing else" do
    freshness = KeywordFreshness.for(keyword)[keyword.id]
    activity = KeywordActivity.for(keyword)[keyword.id]

    data = described_class.call(keyword, freshness, activity)

    expect(data.keys).to include("freshness", "activity")
    expect(data["freshness"].keys).to match_array(%i[state reason last_success_at last_attempt_status last_attempt_at])
    expect(data["activity"].keys).to match_array(%i[recent_runs latency_ms rank])
  end

  it "never includes anything that was not asked for, such as the runs themselves" do
    create(:search_run, keyword: keyword)

    expect(described_class.call(keyword).to_json).not_to include("fingerprint")
  end
end
