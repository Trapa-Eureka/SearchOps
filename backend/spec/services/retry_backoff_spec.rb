require "rails_helper"

RSpec.describe RetryBackoff do
  def with_random(value)
    instance_double(Random, rand: value)
  end

  describe ".delay" do
    it "doubles the ceiling each attempt" do
      ceilings = (1..4).map { |attempt| described_class.delay(attempt, random: with_random(1.0)) }

      expect(ceilings).to eq([ 2.0, 4.0, 8.0, 16.0 ])
    end

    it "never goes below half of the ceiling (equal jitter)" do
      floors = (1..4).map { |attempt| described_class.delay(attempt, random: with_random(0.0)) }

      expect(floors).to eq([ 1.0, 2.0, 4.0, 8.0 ])
    end

    it "caps the delay" do
      expect(described_class.delay(20, random: with_random(1.0))).to eq(described_class::CAP_SECONDS)
      expect(described_class.delay(20, random: with_random(0.0))).to eq(described_class::CAP_SECONDS / 2.0)
    end

    it "stays within [ceiling/2, ceiling] for real random values" do
      200.times do
        delay = described_class.delay(3)
        expect(delay).to be_between(4.0, 8.0)
      end
    end

    it "produces different delays so retries spread out" do
      expect((1..30).map { described_class.delay(4) }.uniq.size).to be > 1
    end

    it "honors a Retry-After hint over the computed delay" do
      expect(described_class.delay(1, retry_after: 45)).to eq(45)
    end

    it "caps an excessive Retry-After" do
      expect(described_class.delay(1, retry_after: 86_400)).to eq(described_class::MAX_RETRY_AFTER_SECONDS)
    end

    it "ignores a zero, negative, or missing Retry-After" do
      expect(described_class.delay(1, retry_after: 0, random: with_random(1.0))).to eq(2.0)
      expect(described_class.delay(1, retry_after: -5, random: with_random(1.0))).to eq(2.0)
      expect(described_class.delay(1, retry_after: nil, random: with_random(1.0))).to eq(2.0)
    end
  end
end
