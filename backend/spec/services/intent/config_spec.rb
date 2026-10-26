require "rails_helper"

RSpec.describe Intent::Config do
  describe ".enabled?" do
    it "is off by default", env: { "LAYA_ENABLED" => nil } do
      expect(described_class.enabled?).to be(false)
    end

    it "reads true values", env: { "LAYA_ENABLED" => "true" } do
      expect(described_class.enabled?).to be(true)
    end

    it "treats anything else as off", env: { "LAYA_ENABLED" => "maybe" } do
      expect(described_class.enabled?).to be(false)
    end
  end

  describe ".min_confidence" do
    it "defaults to 0.7", env: { "LAYA_MIN_CONFIDENCE" => nil } do
      expect(described_class.min_confidence).to eq(0.7)
    end

    it "reads and clamps the environment" do
      ENV["LAYA_MIN_CONFIDENCE"] = "0.85"
      expect(described_class.min_confidence).to eq(0.85)
      ENV["LAYA_MIN_CONFIDENCE"] = "5"
      expect(described_class.min_confidence).to eq(1.0)
      ENV["LAYA_MIN_CONFIDENCE"] = "-1"
      expect(described_class.min_confidence).to eq(0.0)
    ensure
      ENV.delete("LAYA_MIN_CONFIDENCE")
    end

    it "falls back to the default for garbage", env: { "LAYA_MIN_CONFIDENCE" => "high" } do
      expect(described_class.min_confidence).to eq(0.7)
    end
  end

  describe ".timeout_seconds" do
    it "defaults to 4 seconds", env: { "LAYA_TIMEOUT_SECONDS" => nil } do
      expect(described_class.timeout_seconds).to eq(4.0)
    end

    it "clamps absurd values and rejects garbage" do
      ENV["LAYA_TIMEOUT_SECONDS"] = "9999"
      expect(described_class.timeout_seconds).to eq(30.0)
      ENV["LAYA_TIMEOUT_SECONDS"] = "0"
      expect(described_class.timeout_seconds).to eq(4.0)
      ENV["LAYA_TIMEOUT_SECONDS"] = "fast"
      expect(described_class.timeout_seconds).to eq(4.0)
    ensure
      ENV.delete("LAYA_TIMEOUT_SECONDS")
    end
  end

  describe "other settings" do
    it "has local defaults", env: { "LAYA_URL" => nil, "LAYA_MODEL" => nil, "LAYA_API_KEY" => nil, "INTENT_RETENTION_DAYS" => nil } do
      expect(described_class.url).to eq("http://127.0.0.1:8765")
      expect(described_class.model).to eq("multilingual")
      expect(described_class.api_key).to be_nil
      expect(described_class.retention_days).to eq(30)
    end

    it "treats a blank API key as none", env: { "LAYA_API_KEY" => "  " } do
      expect(described_class.api_key).to be_nil
    end

    it "keeps retention positive", env: { "INTENT_RETENTION_DAYS" => "0" } do
      expect(described_class.retention_days).to eq(30)
    end
  end
end
