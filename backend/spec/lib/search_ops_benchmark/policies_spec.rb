require "rails_helper"

RSpec.describe SearchOpsBenchmark::Policies do
  let(:task) { { "query" => "Payment API", "country" => "us", "language" => "en", "target_domain" => "stripe.com" } }
  let(:plan) { { "intent" => "organic_rank_tracking", "query" => " payment   api ", "country" => "US", "language" => "en", "target_domain" => "Stripe.com" } }
  let(:item) { { "intent" => "organic_rank_tracking", "task" => task } }

  describe ".plan_matches_task?" do
    it "ignores case and spacing, and needs the right intent" do
      expect(described_class.plan_matches_task?(plan, task)).to be(true)
      expect(described_class.plan_matches_task?(plan.merge("intent" => "search_history"), task)).to be(false)
      expect(described_class.plan_matches_task?(nil, task)).to be(false)
    end

    it "is false when any single field differs" do
      %w[query country language target_domain].each do |field|
        expect(described_class.plan_matches_task?(plan.merge(field => "different"), task)).to be(false), field
      end
    end
  end

  describe ".edits_needed" do
    it "counts the fields the person has to type or fix" do
      expect(described_class.edits_needed(plan, task)).to eq(0)
      expect(described_class.edits_needed(plan.merge("country" => nil, "language" => "ko"), task)).to eq(2)
      expect(described_class.edits_needed(nil, task)).to eq(4)
    end
  end

  describe SearchOpsBenchmark::Policies::Diligent do
    subject(:policy) { described_class.new }

    it "confirms a ready plan that is what they meant" do
      expect(policy.decide(item, { "status" => "ready", "plan" => plan })).to eq([ :confirm, nil ])
    end

    it "does not confirm a ready plan that is wrong: they use the form instead" do
      expect(policy.decide(item, { "status" => "ready", "plan" => plan.merge("country" => "kr") })).to eq([ :structured ])
    end

    it "completes missing details from what they had in mind" do
      body = { "status" => "needs_clarification", "reason" => "missing_fields", "plan" => plan.merge("country" => nil) }

      expect(policy.decide(item, body)).to eq([ :confirm, task ])
    end

    it "gives up on the sentence when it cannot be completed, or Laya is unavailable" do
      [ { "status" => "needs_clarification", "reason" => "low_confidence", "plan" => nil }, { "status" => "needs_clarification", "reason" => "keyword_not_found", "plan" => plan },
        { "status" => "unavailable", "reason" => "classifier_unavailable", "plan" => nil }, { "status" => "unsupported", "plan" => nil } ].each do |body|
        expect(policy.decide(item, body)).to eq([ :structured ])
      end
    end

    it "does nothing for a sentence that was never a rank check, except read a history plan they asked for" do
      expect(policy.decide({ "intent" => "unsupported" }, { "status" => "ready", "plan" => { "intent" => "search_history" } })).to eq([ :stop ])
      expect(policy.decide({ "intent" => "job_search" }, { "status" => "needs_clarification", "plan" => nil })).to eq([ :stop ])
      expect(policy.decide({ "intent" => "search_history" }, { "status" => "ready", "plan" => { "intent" => "search_history" } })).to eq([ :confirm, nil ])
      expect(policy.decide({ "intent" => "search_history" }, { "status" => "ready", "plan" => { "intent" => "organic_rank_tracking" } })).to eq([ :stop ])
    end
  end

  describe SearchOpsBenchmark::Policies::Careless do
    subject(:policy) { described_class.new }

    it "confirms every ready plan without reading it, and nothing else" do
      expect(policy.decide({ "intent" => "unsupported" }, { "status" => "ready", "plan" => plan })).to eq([ :confirm, nil ])
      expect(policy.decide(item, { "status" => "needs_clarification" })).to eq([ :stop ])
      expect(policy.decide(item, { "status" => "unavailable" })).to eq([ :stop ])
    end
  end
end
