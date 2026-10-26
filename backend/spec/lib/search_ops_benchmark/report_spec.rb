require "rails_helper"

# The report must count what was recorded and nothing else. These use hand-made records whose
# answers can be checked by eye.
RSpec.describe SearchOpsBenchmark::Report do
  def task(query, domain)
    { "query" => query, "country" => "us", "language" => "en", "target_domain" => domain }
  end

  def rec(item_id, ms:, task:, correct: true, **extra)
    { pass: "cold", item_id: item_id, intent: "organic_rank_tracking", lang: "en", has_task: true, task: task, steps: { "search" => ms }, ms: ms, backoff_ms: 0.0,
      provider_calls: 1, failed_attempts: 0, unnecessary_calls: 0, attempt_latencies: [ 900 ], completed: correct, correct: correct, cache_hit: false, fallback: false,
      edits: 0, text_length: 50, rep: 1 }.merge(extra)
  end

  let(:payment) { task("payment api", "stripe.com") }     # 11 + 10 = 21 characters on the form
  let(:wiki) { task("team wiki", "notion.so") }           # 9 + 9 = 18
  let(:meta) do
    { measured_at: "2026-10-26T00:00:00Z", sentences: 2, tasks: 2, laya_warmup_ms: 100, laya_model: "multilingual", laya_version: "x", heldout_sha256: "abc",
      config: { repeats: 1, seed: 1, provider_median_ms: 900, provider_sigma: 0.35, failure_rate: 0.3 } }
  end
  let(:result) do
    a = [ rec(1, ms: 1000, task: payment), rec(2, ms: 1200, task: wiki) ]
    b = [ rec(1, ms: 1100, task: payment, text_length: 60, plan_status: "ready", plan: { "intent" => "organic_rank_tracking" }.merge(payment)),
          rec(2, ms: 1400, task: wiki, text_length: 40, fallback: true, plan_status: "ready", plan: { "intent" => "organic_rank_tracking" }.merge(wiki, "language" => "ko")) ]
    c = [ rec(1, ms: 1010, task: payment), rec(2, ms: 1230, task: wiki) ]
    { meta: meta, repetitions: [ { seed: 1, modes: [ { name: "A", policy: nil, records: a }, { name: "B", policy: "diligent", records: b },
                                                     { name: "C", policy: "laya refusing connections", records: c } ] } ] }
  end
  let(:report) { described_class.new(result) }
  let(:markdown) { report.markdown }

  it "pairs each task with the same task in mode A, so the difference is the mode, not luck" do
    expect(markdown).to include("| B - A, all tasks | 2 | 150 ms | 150 ms | 195 ms | 200 ms |")
    expect(markdown).to include("| B - A, confirmed from the plan | 1 | 100 ms |")
    expect(markdown).to include("| B - A, fell back to the form | 1 | 200 ms |")
    expect(markdown).to include("| C - A, all tasks (a failed sentence, then the form) | 2 | 20 ms |")
  end

  it "leaves a task out of the comparison when either side did not finish it" do
    result[:repetitions].first[:modes].first[:records][0][:correct] = false

    expect(markdown).to include("| B - A, all tasks | 1 | 200 ms |")
  end

  it "counts typing: the form for A, the sentence for B, and both when B falls back" do
    # A: 21 + 18 characters, 2 + 2 picks. B: 60 (item 1) + 40 + 18 (item 2, which fell back) characters, 2 picks (item 2 only).
    expect(markdown).to include("| A (form) | 2.0 | 39 | 4 |")
    expect(markdown).to include("| B (sentence, diligent) | 2.0 | 118 | 2 |")
  end

  it "lists the ready plans that were not what the person meant, field by field" do
    expect(markdown).to include("Of the 2 plans that were ready to confirm, 1 matched the intended task exactly and 1 did not")
    expect(markdown).to include('#2 (en): language "ko" instead of "en"')
  end

  it "reports completion with a Wilson interval, not a bare fraction" do
    expect(markdown).to match(/\| A \| 2\/2 \| 34\.2% to 100\.0% \|/)
  end

  it "prints a missing measurement as n/a, never as zero" do
    result[:repetitions].first[:modes].each { |mode| mode[:records].each { |record| record[:correct] = false } }

    expect(markdown).to include("0/2")
    expect(markdown).to include("n/a")
    expect(markdown).not_to match(/NaN|Infinity/)
  end

  it "gives the extra time of a failed sentence as the paired median, the same number as in the paired table" do
    result[:repetitions].first[:modes] << { name: "C", policy: "laya hanging", records: [] }

    expect(markdown).to include("slower at the median than going straight to the form (mode C minus mode A, paired by task)")
    expect(markdown).to include("is 20 ms slower")
  end

  it "rebuilds the same report from the JSON a run saved" do
    rebuilt = described_class.from_json(JSON.generate(result))

    expect(rebuilt.markdown).to eq(markdown)
  end

  it "skips the typing table for a saved run that did not record sentence lengths" do
    result[:repetitions].first[:modes][1][:records].each { |record| record.delete(:text_length) }

    expect(described_class.from_json(JSON.generate(result)).markdown).not_to include("Typing for the rank-check tasks")
  end

  it "formats means without long decimals" do
    expect(markdown).not_to match(/\d\.\d{4,}/)
  end
end
