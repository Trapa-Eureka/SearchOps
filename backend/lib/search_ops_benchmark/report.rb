module SearchOpsBenchmark
  # Turns the raw records into the tables of docs/benchmarks.md. It only counts and summarises what
  # was recorded: no number is estimated, and a missing measurement is printed as "n/a".
  class Report
    def initialize(result)
      @result = result
      @meta = result[:meta]
    end

    # Rebuilds a report from the JSON a run saved. The structure's keys become symbols; the keys inside a
    # record (steps, plan, task) stay strings, as they were when recorded.
    def self.from_json(text)
      raw = JSON.parse(text)
      new(
        meta: raw["meta"].deep_symbolize_keys,
        repetitions: raw["repetitions"].map do |repetition|
          { seed: repetition["seed"], modes: repetition["modes"].map { |mode| { name: mode["name"], policy: mode["policy"], records: mode["records"].map(&:symbolize_keys) } } }
        end
      )
    end

    # All records of one mode across the repetitions, each tagged with its repetition.
    def records(name, policy = nil)
      @result[:repetitions].flat_map do |repetition|
        repetition[:modes].select { |mode| mode[:name] == name && mode[:policy] == policy }.flat_map { |mode| mode[:records].map { |rec| rec.merge(rep: repetition[:seed]) } }
      end
    end

    def first_repetition(name, policy = nil)
      mode = @result[:repetitions].first[:modes].find { |entry| entry[:name] == name && entry[:policy] == policy }
      mode ? mode[:records] : []
    end

    # ---- numbers

    def tasks(recs, pass)
      recs.select { |rec| rec[:has_task] && rec[:pass] == pass }
    end

    def completion(recs)
      tasks = tasks(recs, "cold")
      done = tasks.count { |rec| rec[:correct] }
      { n: tasks.size, done: done, rate: Stats.rate(done, tasks.size), interval: Stats.wilson(done, tasks.size) }
    end

    def latency(recs, with_backoff: false)
      done = tasks(recs, "cold").select { |rec| rec[:correct] }
      Stats.summary(done.map { |rec| rec[:ms] + (with_backoff ? rec[:backoff_ms] : 0) })
    end

    def step_latency(recs, step)
      Stats.summary(recs.filter_map { |rec| rec[:steps][step] })
    end

    def calls(recs, pass: nil)
      selected = pass ? recs.select { |rec| rec[:pass] == pass } : recs
      { calls: selected.sum { |rec| rec[:provider_calls] }, failed_attempts: selected.sum { |rec| rec[:failed_attempts] },
        unnecessary: selected.sum { |rec| rec[:unnecessary_calls] }, runs_failed: selected.count { |rec| rec[:run_status] == "failed" } }
    end

    def cache(recs)
      warm = tasks(recs, "warm")
      hits = warm.count { |rec| rec[:cache_hit] }
      { n: warm.size, hits: hits, rate: Stats.rate(hits, warm.size), calls: warm.sum { |rec| rec[:provider_calls] }, latency: Stats.summary(warm.map { |rec| rec[:ms] }) }
    end

    # ---- rendering

    def markdown
      [ header, completion_table, paired_table, time_table, language_model_table, mistakes_table, cache_table, down_table, effort_table, cost_note ].compact.join("\n\n") + "\n"
    end

    def to_json(*)
      JSON.pretty_generate(@result)
    end

    private

    def ms(value)
      value.nil? ? "n/a" : "#{value.round} ms"
    end

    def pct(value)
      value.nil? ? "n/a" : format("%.1f%%", value * 100)
    end

    def interval(pair)
      pair ? "#{pct(pair[0])} to #{pct(pair[1])}" : "n/a"
    end

    def pair(stats)
      "#{ms(stats[:p50])} / #{ms(stats[:p95])}"
    end

    def table(headers, rows)
      ([ "| #{headers.join(' | ')} |", "|#{headers.map { '---' }.join('|')}|" ] + rows.map { |row| "| #{row.join(' | ')} |" }).join("\n")
    end

    def label(name, policy)
      policy ? "#{name} (#{policy})" : name
    end

    def modes_with_tasks
      [ [ "A", nil ], [ "B", "diligent" ], [ "C", "laya refusing connections" ] ].select { |name, policy| records(name, policy).any? }
    end

    def header
      c = @meta[:config]
      "Measured #{@meta[:measured_at]} · #{@meta[:sentences]} sentences (#{@meta[:tasks]} rank-check tasks) · #{c[:repeats]} repetitions · seed #{c[:seed]} · " \
        "fake provider: median #{c[:provider_median_ms]} ms, sigma #{c[:provider_sigma]}, #{(c[:failure_rate] * 100).round}% of attempts fail · held-out set #{@meta[:heldout_sha256]} · " \
        "Laya #{@meta[:laya_model]} #{@meta[:laya_version]}"
    end

    def completion_table
      rows = modes_with_tasks.map do |name, policy|
        recs = records(name, policy)
        done = completion(recs)
        measured = latency(recs)
        waited = latency(recs, with_backoff: true)
        count = calls(recs, pass: "cold")
        [ label(name, policy), "#{done[:done]}/#{done[:n]}", interval(done[:interval]), pair(measured), pair(waited), count[:calls], count[:failed_attempts], count[:runs_failed] ]
      end
      "**Getting a rank check done** (cold pass, every task, all repetitions)\n\n" +
        table([ "mode", "done correctly", "95% interval", "time to result p50 / p95", "with retry waiting p50 / p95", "SerpApi calls", "attempts that failed", "runs that failed" ], rows)
    end

    def time_table
      rows = []
      modes_with_tasks.each do |name, policy|
        recs = records(name, policy)
        %w[plan confirm create_keyword search].each do |step|
          stats = step_latency(recs.select { |rec| rec[:pass] == "cold" }, step)
          rows << [ label(name, policy), step, stats[:n], pair(stats) ] if stats[:n].positive?
        end
      end
      laya = Stats.summary(records("B", "diligent").select { |rec| rec[:pass] == "cold" }.map { |rec| rec[:laya_ms] })
      rows << [ "B (diligent)", "Laya classification (inside plan)", laya[:n], pair(laya) ]
      attempts = Stats.summary(records("A").flat_map { |rec| rec[:attempt_latencies] })
      rows << [ "A", "fake provider, one attempt", attempts[:n], pair(attempts) ]
      "**Where the time goes** (cold pass, per request)\n\n" + table([ "mode", "step", "n", "p50 / p95" ], rows)
    end

    def language_model_table
      recs = first_repetition("B", "diligent").select { |rec| rec[:pass] == "cold" }
      return nil if recs.empty?

      correct = recs.count { |rec| rec[:predicted_intent] == rec[:intent] }
      lines = [ "**Natural language (B, diligent), one repetition, #{recs.size} sentences**", "",
                "- intent classification: #{correct}/#{recs.size} = #{pct(Stats.rate(correct, recs.size))} (95% interval #{interval(Stats.wilson(correct, recs.size))})",
                "- plans the validator rejected: #{recs.count { |rec| rec[:plan_errors] }}; confirmations the API refused: #{recs.count { |rec| rec[:decision] == 'confirm' && rec[:error_code] }}" ]
      rows = Intent::Catalog::INTENTS.map do |intent|
        group = recs.select { |rec| rec[:intent] == intent }
        statuses = group.map { |rec| [ rec[:plan_status], rec[:plan_reason] ].compact.join("/") }.tally.sort_by { |_, n| -n }.map { |name, n| "#{name} #{n}" }.join(", ")
        decisions = group.map { |rec| rec[:decision] }.tally.map { |name, n| "#{name} #{n}" }.join(", ")
        [ intent, group.size, statuses, decisions ]
      end
      tasks = recs.select { |rec| rec[:has_task] }
      lines << "- of the #{tasks.size} rank-check sentences: #{tasks.count { |rec| !rec[:fallback] && rec[:decision] == 'confirm' }} confirmed from the plan " \
               "(#{tasks.count { |rec| rec[:decision] == 'confirm' && rec[:edits].positive? }} needed typing or fixing, on average #{format('%.1f', Stats.mean(tasks.map { |rec| rec[:edits] }) || 0)} fields), " \
               "#{tasks.count { |rec| rec[:fallback] }} fell back to the keyword form"
      lines.join("\n") + "\n\n" + table([ "true intent", "n", "what the planner answered", "what the person did" ], rows) + field_accuracy(tasks)
    end

    # For the rank-check sentences: what the plan said for each field, against what the person meant. A
    # field that is "not provided" is asked for; a "wrong" one is a silent misreading that only the
    # person's confirmation stands in front of.
    def field_accuracy(tasks)
      planned = tasks.select { |rec| rec[:plan].present? && rec[:plan]["intent"] == "organic_rank_tracking" }
      return "" if planned.empty?

      rows = Policies::FIELDS.map do |field|
        right = planned.count { |rec| rec[:plan][field].present? && Policies.normalize(rec[:plan][field]) == Policies.normalize(rec[:task][field]) }
        missing = planned.count { |rec| rec[:plan][field].blank? }
        [ field, right, planned.size - right - missing, missing ]
      end
      ready = planned.select { |rec| rec[:plan_status] == "ready" }
      matching = ready.count { |rec| Policies.plan_matches_task?(rec[:plan], rec[:task]) }
      wrong = ready.reject { |rec| Policies.plan_matches_task?(rec[:plan], rec[:task]) }.map do |rec|
        fields = Policies::FIELDS.reject { |field| Policies.normalize(rec[:plan][field]) == Policies.normalize(rec[:task][field]) }
        "##{rec[:item_id]} (#{rec[:lang]}): " + fields.map { |field| "#{field} #{rec[:plan][field].inspect} instead of #{rec[:task][field].inspect}" }.join(", ")
      end
      "\n\n**Plan fields against what the person meant** (the #{planned.size} rank-check sentences that got a rank-check plan)\n\n" +
        table([ "field", "right", "wrong", "not provided (asked for)" ], rows) +
        "\n\nOf the #{ready.size} plans that were ready to confirm, #{matching} matched the intended task exactly and #{ready.size - matching} did not" +
        (wrong.any? ? ":\n\n#{wrong.map { |line| "- #{line}" }.join("\n")}" : ".")
    end

    # The same task in two modes sees the same provider latencies and failures (the fake provider is seeded
    # per search), so the difference of their times is the cost of the mode itself, not luck.
    # Time of each finished task in the given mode minus the time of the same task in mode A.
    def paired_differences(mode_records, &filter)
      base = tasks(records("A"), "cold").select { |rec| rec[:correct] }.to_h { |rec| [ [ rec[:rep], rec[:item_id] ], rec ] }
      tasks(mode_records, "cold").filter_map do |rec|
        mate = base[[ rec[:rep], rec[:item_id] ]]
        rec[:ms] - mate[:ms] if rec[:correct] && mate && (filter.nil? || filter.call(rec))
      end
    end

    def paired_table
      rows = []
      add = lambda do |label, mode_records, &filter|
        diffs = paired_differences(mode_records, &filter)
        stats = Stats.summary(diffs)
        rows << [ label, stats[:n], ms(stats[:p50]), ms(stats[:mean]), ms(stats[:p95]), ms(diffs.max) ] if diffs.any?
      end
      b = records("B", "diligent")
      add.call("B - A, all tasks", b)
      add.call("B - A, confirmed from the plan", b) { |rec| !rec[:fallback] }
      add.call("B - A, fell back to the form", b) { |rec| rec[:fallback] }
      add.call("C - A, all tasks (a failed sentence, then the form)", records("C", "laya refusing connections"))
      return nil if rows.empty?

      "**Extra time per task compared with the form** (paired by task and repetition; positive = slower than A)\n\n" +
        table([ "comparison", "n", "median", "mean", "p95", "max" ], rows)
    end

    # Typing is the one thing a sentence is supposed to save. Counted as characters typed into text fields
    # (the query and the domain on the form; the whole sentence in B) and drop-downs picked (country and
    # language). A proxy for effort, not a usability study.
    def effort_table
      per_rep = @result[:repetitions].size.to_f
      form = ->(task) { [ task["query"].length + task["target_domain"].length, 2 ] }
      a = records("A", nil).select { |rec| rec[:pass] == "cold" }
      a_chars = a.sum { |rec| form.call(rec[:task]).first } / per_rep
      a_picks = a.sum { |rec| form.call(rec[:task]).last } / per_rep
      rows = [ [ "A (form)", a.size / per_rep, format("%.0f", a_chars), format("%.0f", a_picks) ] ]
      b = records("B", "diligent").select { |rec| rec[:pass] == "cold" && rec[:has_task] }
      return nil if b.any? { |rec| rec[:text_length].nil? } # a run saved before sentence lengths were recorded
      return "**Typing**\n\n" + table([ "mode", "tasks per repetition", "characters typed", "drop-downs picked" ], rows) if b.empty?

      chars = b.sum { |rec| rec[:text_length] + (rec[:fallback] ? form.call(rec[:task]).first : 0) } / per_rep
      picks = b.sum { |rec| rec[:fallback] ? form.call(rec[:task]).last : 0 } / per_rep
      rows << [ "B (sentence, diligent)", b.size / per_rep, format("%.0f", chars), format("%.0f", picks) ]
      "**Typing for the rank-check tasks** (mean per repetition; a sentence that fell back to the form is typed AND filled in)\n\n" +
        table([ "mode", "tasks per repetition", "characters typed", "drop-downs picked" ], rows)
    end

    def mistakes_table
      rows = [ [ "B", "diligent" ], [ "B", "careless" ] ].filter_map do |name, policy|
        recs = records(name, policy).select { |rec| rec[:pass] == "cold" }
        next if recs.empty?

        per_rep = @result[:repetitions].size
        confirmed = recs.count { |rec| rec[:decision] == "confirm" }
        [ label(name, policy), recs.size / per_rep, format("%.1f", confirmed / per_rep.to_f), format("%.1f", recs.sum { |rec| rec[:provider_calls] } / per_rep.to_f),
          format("%.1f", recs.sum { |rec| rec[:unnecessary_calls] } / per_rep.to_f), format("%.1f", recs.count { |rec| rec[:executed_kind] == "search" && !rec[:has_task] } / per_rep.to_f) ]
      end
      "**Cost of misreadings** (cold pass, mean per repetition)\n\n" +
        table([ "B policy", "sentences", "plans confirmed", "SerpApi calls", "calls that should not have been made", "searches started for a sentence with no rank-check task" ], rows)
    end

    def cache_table
      rows = modes_with_tasks.map do |name, policy|
        warm = cache(records(name, policy))
        [ label(name, policy), "#{warm[:hits]}/#{warm[:n]}", pct(warm[:rate]), warm[:calls], pair(warm[:latency]) ]
      end
      "**Second pass over the same tasks** (cache warm)\n\n" + table([ "mode", "cache hits", "hit rate", "SerpApi calls", "time p50 / p95" ], rows)
    end

    def down_table
      refusing = records("C", "laya refusing connections").select { |rec| rec[:pass] == "cold" }
      hanging = records("C", "laya hanging")
      return nil if refusing.empty?

      plan = Stats.summary(refusing.filter_map { |rec| rec[:steps]["plan"] })
      rows = [ [ "connection refused", plan[:n], pair(plan) ] ]
      rows << [ "no answer (client timeout #{Intent::Config.timeout_seconds} s)", hanging.size, hanging.map { |rec| ms(rec[:steps]["plan"]) }.join(", ") ] if hanging.any?
      overhead = Stats.percentile(paired_differences(records("C", "laya refusing connections")), 0.5)
      "**What a person waits for the fallback when Laya is down**\n\n" + table([ "Laya is", "n", "time for the sentence to get its fallback (p50 / p95, or each)" ], rows) +
        "\n\nA task done through the keyword form after a failed sentence is #{ms(overhead)} slower at the median than going straight to the form (mode C minus mode A, paired by task)."
    end

    def cost_note
      calls = modes_with_tasks.map { |name, policy| "#{label(name, policy)}: #{calls(records(name, policy)).fetch(:calls)}" }.join("; ")
      "**Cost.** SerpApi calls over the whole run (both passes, all repetitions): #{calls}. Cost = calls x the plan's price per search, which is read from the " \
        "account or the current pricing page and not assumed here. Laya runs locally: no per-request fee, only its CPU or GPU time (see its latency above)."
    end
  end
end
