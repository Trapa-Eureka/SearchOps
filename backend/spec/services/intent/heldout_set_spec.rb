require "rails_helper"

# The held-out set is only worth something if it stays what it claims to be. These checks guard its
# shape, not its labels: whether a label is right is a judgement the specs cannot make.
RSpec.describe "Held-out evaluation set" do
  let(:data) { JSON.parse(Rails.root.join("spec/fixtures/intent/heldout_set.json").read) }
  let(:items) { data["items"] }
  let(:old_texts) { JSON.parse(Rails.root.join("spec/fixtures/intent/eval_set.json").read)["items"].map { |item| item["text"] } }

  it "has 20 sentences per intent, with unique ids and unique texts" do
    expect(items.size).to eq(80)
    expect(items.group_by { |item| item["intent"] }.transform_values(&:size)).to eq(Intent::Catalog::INTENTS.index_with { 20 })
    expect(items.map { |item| item["id"] }).to eq((1..80).to_a)
    expect(items.map { |item| item["text"] }.uniq.size).to eq(80)
  end

  it "shares no sentence with the development and test sets" do
    expect(items.map { |item| item["text"] } & old_texts).to eq([])
  end

  it "fits what the planner accepts as input" do
    expect(items).to all(satisfy { |item| item["text"].length <= IntentRequest::TEXT_MAX_LENGTH && item["text"].match?(/\S/) })
  end

  it "labels flags only for supported intents, and as booleans" do
    items.each do |item|
      if item["intent"] == "unsupported"
        expect(item).not_to include("compare_previous", "only_new")
      else
        expect([ item["compare_previous"], item["only_new"] ]).to all(satisfy { |value| [ true, false ].include?(value) })
      end
    end
  end

  it "gives every rank-tracking sentence a structured task that the keyword form would accept" do
    ranks = items.select { |item| item["intent"] == "organic_rank_tracking" }

    ranks.each do |item|
      keyword = Keyword.new(item["task"].slice("query", "country", "language", "target_domain"))
      expect(keyword).to be_valid, "item #{item['id']}: #{keyword.errors.full_messages.to_sentence}"
    end
    expect(items.reject { |item| item["intent"] == "organic_rank_tracking" }).to all(satisfy { |item| !item.key?("task") })
  end

  it "covers several languages, so it is not an English-only test" do
    expect(items.map { |item| item["lang"] }.uniq).to include("en", "ko", "ja", "tl", "es", "de", "fr")
  end
end
