namespace :searchops do
  desc "Measure the intent classifier on spec/fixtures/intent/eval_set.json (SPLIT=dev|test|all, needs laya-serve running)"
  task :intent_eval, [ :split ] => :environment do |_task, args|
    split = (args[:split] || ENV.fetch("SPLIT", "dev")).to_s
    data = JSON.parse(Rails.root.join("spec/fixtures/intent/eval_set.json").read)
    items = data["items"].select { |item| split == "all" || item["split"] == split }
    abort "No items for split #{split.inspect}" if items.empty?

    classifier = Intent::LayaClassifier.from_env
    min = Intent::Config.min_confidence

    begin
      classifier.classify("warm-up")
    rescue Intent::ClassifierError => error
      abort "laya-serve is not usable (#{error.category}): #{error.message}. Start it with scripts/laya-serve.sh and set LAYA_ENABLED=true."
    end

    rows = items.map do |item|
      extraction = Intent::Extractor.call(item["text"])
      classification = classifier.classify(extraction.masked_text)
      # The full planner, rolled back so the evaluation sentences are never stored.
      outcome = nil
      ActiveRecord::Base.transaction do
        outcome = Intent::Planner.new(classifier: classifier, enabled: true).call(item["text"])
        raise ActiveRecord::Rollback
      end
      { item: item, c: classification, e: extraction, outcome: outcome }
    end

    pct = ->(num, den) { den.zero? ? "n/a" : format("%.1f%% (%d/%d)", 100.0 * num / den, num, den) }

    puts "Intent evaluation: split=#{split} n=#{rows.size} model=#{Intent::Config.model} version=#{Intent::Config.version_label} min_confidence=#{min}"

    correct = rows.count { |r| r[:c].intent == r[:item]["intent"] }
    puts "\nIntent, top-1 over all inputs:   #{pct.call(correct, rows.size)}"
    %w[en ko ja tl es de fr id].each do |lang|
      subset = rows.select { |r| r[:item]["lang"] == lang }
      next if subset.empty?

      puts "  #{lang}: #{pct.call(subset.count { |r| r[:c].intent == r[:item]['intent'] }, subset.size)}"
    end

    answered = rows.select { |r| r[:c].confidence >= min }
    puts "\nAt min_confidence #{min}: answered #{pct.call(answered.size, rows.size)}, accuracy when answered #{pct.call(answered.count { |r| r[:c].intent == r[:item]['intent'] }, answered.size)}"
    puts "  Clarification rate (below threshold): #{pct.call(rows.size - answered.size, rows.size)}"

    puts "\nConfusion matrix (rows = true intent, columns = predicted), all inputs:"
    labels = Intent::Catalog::INTENTS
    puts "  #{'true \\ pred'.ljust(24)}#{labels.map { |l| l[0, 6].rjust(8) }.join}"
    labels.each do |truth|
      line = labels.map { |pred| rows.count { |r| r[:item]["intent"] == truth && r[:c].intent == pred }.to_s.rjust(8) }.join
      puts "  #{truth.ljust(24)}#{line}"
    end

    puts "\nSafety (inputs whose true intent is unsupported, #{rows.count { |r| r[:item]['intent'] == 'unsupported' }} total):"
    unsupported = rows.select { |r| r[:item]["intent"] == "unsupported" }
    proposed = unsupported.select { |r| %w[planned needs_clarification].include?(r[:outcome].outcome) && r[:outcome].plan.present? }
    puts "  turned into a plan (planned or completable): #{pct.call(proposed.size, unsupported.size)}"
    puts "  planned, i.e. ready to confirm:             #{pct.call(unsupported.count { |r| r[:outcome].outcome == 'planned' }, unsupported.size)}"
    wrong_confident = rows.select { |r| r[:c].confidence >= min && r[:c].intent != r[:item]["intent"] }
    puts "  confident but wrong (any intent):           #{pct.call(wrong_confident.size, rows.size)}"

    puts "\nPlanner outcome by true intent:"
    rows.group_by { |r| r[:item]["intent"] }.each do |truth, group|
      counts = group.map { |r| r[:outcome].outcome + (r[:outcome].fallback_reason ? "/#{r[:outcome].fallback_reason}" : "") }.tally.sort_by { |_, n| -n }
      puts "  #{truth.ljust(24)}#{counts.map { |name, n| "#{name}=#{n}" }.join('  ')}"
    end

    flagged = rows.reject { |r| r[:item]["compare_previous"].nil? }
    puts "\nFlags (rule-based) on inputs with a supported intent (n=#{flagged.size}); precision / recall:"
    { "compare_previous" => :compare_cue, "only_new" => :only_new_cue }.each do |flag, cue|
      truth = flagged.count { |r| r[:item][flag] }
      tp = flagged.count { |r| r[:e].public_send(cue) && r[:item][flag] }
      fp = flagged.count { |r| r[:e].public_send(cue) && !r[:item][flag] }
      fn = flagged.count { |r| !r[:e].public_send(cue) && r[:item][flag] }
      puts "  #{flag.ljust(17)} (#{truth} true)  precision #{pct.call(tp, tp + fp).ljust(16)} recall #{pct.call(tp, tp + fn)}"
    end

    latencies = rows.map { |r| r[:c].latency_ms }.sort
    puts "\nLaya latency per request: p50 #{latencies[latencies.size / 2]} ms, p95 #{latencies[(latencies.size * 0.95).floor]} ms, max #{latencies.last} ms"
  end
end
