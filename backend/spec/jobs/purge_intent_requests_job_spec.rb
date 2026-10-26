require "rails_helper"

RSpec.describe PurgeIntentRequestsJob do
  it "deletes expired requests and logs only a count" do
    create(:intent_request, original_text: "very private sentence", created_at: 40.days.ago)
    create(:intent_request, created_at: 1.day.ago)
    allow(Rails.logger).to receive(:info)

    expect { described_class.perform_now }.to change(IntentRequest, :count).from(2).to(1)

    expect(Rails.logger).to have_received(:info).with("intent_purge deleted=1 retention_days=30")
    expect(Rails.logger).not_to have_received(:info).with(a_string_including("private"))
  end

  it "is a no-op when nothing has expired" do
    create(:intent_request)

    expect { described_class.perform_now }.not_to change(IntentRequest, :count)
  end

  it "is scheduled to run daily" do
    config = YAML.safe_load(Rails.root.join("config/recurring.yml").read, aliases: true)

    expect(config.dig("production", "purge_intent_requests")).to include("class" => "PurgeIntentRequestsJob")
    expect(config.dig("development", "purge_intent_requests")).to include("class" => "PurgeIntentRequestsJob")
  end
end
