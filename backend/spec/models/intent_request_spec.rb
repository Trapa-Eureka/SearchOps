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
    %w[executed_all ready failed rejected].each { |outcome| expect(build(:intent_request, outcome: outcome)).not_to be_valid }
  end

  it "rejects negative durations" do
    expect(build(:intent_request, duration_ms: -5)).not_to be_valid
  end

  it "allows a missing plan for unsupported requests" do
    request = build(:intent_request, plan: nil, outcome: "unsupported", fallback_reason: "out_of_scope")
    expect(request).to be_valid
  end

  it "defaults the analysis to an empty object" do
    expect(described_class.new.analysis).to eq({})
  end

  describe ".purge_expired" do
    it "deletes requests older than the retention period and keeps newer ones" do
      old = create(:intent_request, created_at: 31.days.ago)
      recent = create(:intent_request, created_at: 29.days.ago)

      expect(described_class.purge_expired).to eq(1)
      expect(described_class.all).to contain_exactly(recent)
      expect(described_class.exists?(old.id)).to be(false)
    end

    it "uses the configured retention", env: { "INTENT_RETENTION_DAYS" => "7" } do
      create(:intent_request, created_at: 8.days.ago)
      keep = create(:intent_request, created_at: 6.days.ago)

      described_class.purge_expired

      expect(described_class.all).to contain_exactly(keep)
    end

    it "does not touch keywords or runs created by a confirmed plan" do
      keyword = create(:keyword)
      create(:intent_request, created_at: 90.days.ago, outcome: "executed", execution: { "keyword_id" => keyword.id })

      described_class.purge_expired

      expect(Keyword.exists?(keyword.id)).to be(true)
    end
  end
end
