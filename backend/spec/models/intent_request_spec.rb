require "rails_helper"

RSpec.describe IntentRequest, type: :model do
  it "has a valid factory" do
    expect(build(:intent_request)).to be_valid
  end

  it "requires the original text and limits its length" do
    expect(build(:intent_request, original_text: "")).not_to be_valid
    expect(build(:intent_request, original_text: "a" * IntentRequest::TEXT_MAX_LENGTH)).to be_valid
    expect(build(:intent_request, original_text: "a" * (IntentRequest::TEXT_MAX_LENGTH + 1))).not_to be_valid
  end

  it "accepts only known outcomes" do
    IntentRequest::OUTCOMES.each do |outcome|
      expect(build(:intent_request, outcome: outcome)).to be_valid
    end
    expect(build(:intent_request, outcome: "executed")).not_to be_valid
  end

  it "rejects negative durations" do
    expect(build(:intent_request, duration_ms: -5)).not_to be_valid
  end

  it "allows a missing plan for unsupported requests" do
    request = build(:intent_request, plan: nil, outcome: "unsupported", fallback_reason: "low_confidence")
    expect(request).to be_valid
  end
end
