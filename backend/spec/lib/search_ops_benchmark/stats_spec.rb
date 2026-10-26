require "rails_helper"

RSpec.describe SearchOpsBenchmark::Stats do
  describe ".percentile" do
    it "interpolates between ranks, like the metrics endpoint" do
      expect(described_class.percentile([ 100, 200, 300, 400 ], 0.5)).to eq(250)
      expect(described_class.percentile([ 100, 200, 300, 400 ], 0.95)).to be_within(0.001).of(385)
      expect(described_class.percentile([ 7 ], 0.95)).to eq(7)
    end

    it "does not need sorted input and ignores missing values" do
      expect(described_class.percentile([ 400, nil, 100, 300, 200 ], 0.5)).to eq(250)
    end

    it "is nil, not zero, with no data" do
      expect(described_class.percentile([], 0.5)).to be_nil
      expect(described_class.percentile([ nil ], 0.5)).to be_nil
    end
  end

  describe ".summary" do
    it "gives n, p50, p95, max, and mean" do
      expect(described_class.summary([ 1, 2, 3, 4, 100 ])).to include(n: 5, p50: 3, max: 100, mean: 22.0)
    end

    it "reports nothing as nothing" do
      expect(described_class.summary([])).to eq(n: 0, p50: nil, p95: nil, max: nil, mean: nil)
    end
  end

  describe ".wilson" do
    it "matches the known 95% score intervals" do
      low, high = described_class.wilson(5, 10)
      expect(low).to be_within(0.001).of(0.2366)
      expect(high).to be_within(0.001).of(0.7634)

      low, high = described_class.wilson(0, 10)
      expect(low).to eq(0.0)
      expect(high).to be_within(0.001).of(0.2775)

      low, high = described_class.wilson(10, 10)
      expect(low).to be_within(0.001).of(0.7225)
      expect(high).to eq(1.0)
    end

    it "narrows as the sample grows" do
      small = described_class.wilson(7, 10)
      large = described_class.wilson(70, 100)

      expect(large[1] - large[0]).to be < (small[1] - small[0])
    end

    it "is nil without a sample, instead of dividing by zero" do
      expect(described_class.wilson(0, 0)).to be_nil
      expect(described_class.wilson(0, nil)).to be_nil
    end
  end

  describe ".rate" do
    it "is a fraction, or nil without a total" do
      expect(described_class.rate(1, 4)).to eq(0.25)
      expect(described_class.rate(0, 0)).to be_nil
    end
  end
end
