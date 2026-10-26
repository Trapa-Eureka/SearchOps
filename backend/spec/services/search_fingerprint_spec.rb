require "rails_helper"

RSpec.describe SearchFingerprint do
  def request(**overrides)
    SearchProvider::Request.new(
      **{ query: "React Developer", engine: "google", country: "ph", language: "en", location: "Manila" }.merge(overrides)
    )
  end

  it "is a 64-character hex digest" do
    expect(described_class.call(request)).to match(/\A\h{64}\z/)
  end

  it "is stable for identical settings" do
    expect(described_class.call(request)).to eq(described_class.call(request))
  end

  it "ignores case and repeated whitespace in query and location" do
    expect(described_class.call(request(query: "  react   DEVELOPER ", location: "MANILA")))
      .to eq(described_class.call(request))
  end

  it "treats a missing location and a blank location the same" do
    expect(described_class.call(request(location: nil))).to eq(described_class.call(request(location: "  ")))
  end

  %i[query engine country language location].each do |field|
    it "changes when #{field} changes" do
      other = { query: "vue", engine: "bing", country: "us", language: "ko", location: "Cebu" }.fetch(field)

      expect(described_class.call(request(field => other))).not_to eq(described_class.call(request))
    end
  end

  it "does not confuse field boundaries" do
    first = request(query: "a b", country: "ph")
    second = request(query: "a", country: "b ph")

    expect(described_class.call(first)).not_to eq(described_class.call(second))
  end
end
