module Intent
  # Turns one sentence into a stored IntentRequest holding a proposal, never an action.
  #
  #   1. The text is checked (length, control characters). Invalid text is rejected unstored.
  #   2. Rules extract country, domain, and query candidates (Intent::Extractor).
  #   3. If Laya is enabled, it classifies the intent and the two flags (Intent::LayaClassifier).
  #   4. The result is decided: below the confidence threshold nothing is proposed, an
  #      out-of-scope intent is reported as such, otherwise a plan is built and validated.
  #
  # Nothing here searches. A plan is executed only by Intent::Executor after confirmation, and
  # when Laya is disabled or down the core search flow is unaffected.
  class Planner
    class Rejected < StandardError
      attr_reader :code

      def initialize(code)
        super(code)
        @code = code
      end
    end

    def self.normalize_text(text)
      raise Rejected, "text_required" if text.nil?
      raise Rejected, "text_must_be_a_string" unless text.is_a?(String)

      value = text.squish
      raise Rejected, "text_required" if value.empty?
      raise Rejected, "text_too_long" if value.length > IntentRequest::TEXT_MAX_LENGTH
      raise Rejected, "text_has_control_characters" if text.match?(/[[:cntrl:]&&[^\s]]/)

      value
    end

    def initialize(classifier: nil, enabled: Config.enabled?, min_confidence: Config.min_confidence)
      @enabled = enabled
      @min_confidence = min_confidence
      @classifier = classifier
    end

    def call(raw_text)
      text = self.class.normalize_text(raw_text)
      started = monotonic_ms
      extraction = Extractor.call(text)

      outcome =
        if !@enabled
          unavailable("laya_disabled", extraction)
        else
          classify_and_decide(text, extraction)
        end

      record(text, outcome, monotonic_ms - started)
    end

    private

    Outcome = Data.define(:status, :reason, :plan, :analysis, :classification)

    def classify_and_decide(text, extraction)
      # The keyword and domain are replaced by neutral words first (Extraction#masked_text), so the
      # topic of the user's keyword cannot decide the intent and Laya never receives them.
      classification = classifier.classify(extraction.masked_text)
      decide(text, extraction, classification)
    rescue ClassifierError => error
      unavailable("classifier_#{error.category}", extraction)
    end

    def classifier
      @classifier ||= LayaClassifier.from_env
    end

    def decide(text, extraction, classification)
      analysis = base_analysis(classification)

      if classification.confidence < @min_confidence
        analysis[:candidates] = top_candidates(classification)
        analysis[:prefill] = prefill(extraction)
        return Outcome.new(status: "needs_clarification", reason: "low_confidence", plan: nil, analysis: analysis,
                           classification: classification)
      end

      if classification.intent == "unsupported"
        return Outcome.new(status: "unsupported", reason: "out_of_scope", plan: nil, analysis: analysis,
                           classification: classification)
      end

      build_plan(text, extraction, classification, analysis)
    end

    def build_plan(text, extraction, classification, analysis)
      intent = classification.intent
      proposed = { "intent" => intent }
      fields = { "intent" => { source: "laya", confidence: classification.confidence.round(4) } }
      notes = []

      add_extracted(proposed, fields, extraction, intent)
      add_flags(proposed, fields, extraction)
      keyword_problem = resolve_history_keyword(proposed, fields, extraction, text) if intent == "search_history"

      validation = PlanValidator.call(proposed)
      analysis[:fields] = fields
      analysis[:missing] = validation.missing
      analysis[:errors] = validation.errors
      analysis[:query_suggestions] = extraction.query_candidates if validation.missing.include?("query")
      analysis[:candidates] = [] # filled only when clarifying
      analysis[:history] = history_for(validation.plan, notes)
      analysis[:notes] = notes
      analysis[:prefill] = prefill(extraction)
      analysis[:country_candidates] = extraction.country_candidates if extraction.country_candidates.size > 1
      analysis[:domain_candidates] = extraction.domain_candidates if extraction.domain_candidates.size > 1

      status, reason =
        if keyword_problem
          analysis[:keyword_candidates] = keyword_problem[:candidates]
          [ "needs_clarification", keyword_problem[:reason] ]
        elsif validation.errors.any?
          [ "needs_clarification", "invalid_fields" ]
        elsif validation.missing.any?
          [ "needs_clarification", "missing_fields" ]
        elsif Keyword::ENGINES.exclude?(validation.plan["engine"])
          notes << "engine_not_implemented"
          [ "unsupported", "engine_not_available" ]
        else
          [ "planned", nil ]
        end

      Outcome.new(status: status, reason: reason, plan: validation.plan, analysis: analysis, classification: classification)
    end

    def add_extracted(proposed, fields, extraction, intent)
      return if intent == "search_history"

      proposed["query"] = extraction.query
      fields["query"] = { source: extraction.query ? "rule" : "missing", evidence: extraction.query }
      proposed["country"] = extraction.country
      fields["country"] = { source: extraction.country ? "rule" : "missing", evidence: extraction.country_evidence }
      proposed["language"] = extraction.language
      fields["language"] = { source: extraction.language ? "rule" : "missing", derived_from: (extraction.country ? "country" : nil) }
      return unless intent == "organic_rank_tracking"

      proposed["target_domain"] = extraction.target_domain
      fields["target_domain"] = { source: extraction.target_domain ? "rule" : "missing", evidence: extraction.target_domain }
    end

    # The two flags come from word lists only (see Intent::Catalog.questions for why). The
    # matched cue is kept so the user can see why a flag is on and switch it off when confirming.
    def add_flags(proposed, fields, extraction)
      { "compare_previous" => extraction.compare_cue, "only_new" => extraction.only_new_cue }.each do |name, cue|
        proposed[name] = cue
        fields[name] = { source: cue ? "rule" : "default" }
      end
    end

    # "Show the history for X": match X against stored keywords by query text or domain.
    # Returns nil when fine, or a problem hash when the request names something ambiguous or unknown.
    def resolve_history_keyword(proposed, fields, extraction, text)
      lowered = text.downcase
      known = Keyword.pluck(:id, :query, :target_domain)
      matches = known.select do |_id, query, domain|
        lowered.include?(query.downcase) || (domain.present? && extraction.domain_candidates.include?(domain))
      end

      if matches.one?
        proposed["keyword_id"] = matches.first.first
        fields["keyword_id"] = { source: "rule", evidence: matches.first[1] }
        nil
      elsif matches.size > 1
        { reason: "ambiguous_keyword", candidates: matches.first(5).map { |id, query, domain| { id: id, query: query, target_domain: domain } } }
      elsif extraction.query || extraction.domain_candidates.any?
        { reason: "keyword_not_found", candidates: [] }
      else
        fields["keyword_id"] = { source: "default", scope: "all_keywords" }
        nil
      end
    end

    # Does earlier data exist to compare with? If not, only a baseline can be created now.
    def history_for(plan, notes)
      return nil unless plan["compare_previous"] && plan["intent"] != "job_search"

      keyword = existing_keyword(plan)
      snapshots = keyword ? keyword.rank_snapshots.count : 0
      notes << "baseline_only" if snapshots.zero? && plan["intent"] == "organic_rank_tracking"
      { keyword_id: keyword&.id, snapshots: snapshots }
    end

    def existing_keyword(plan)
      return Keyword.find_by(id: plan["keyword_id"]) if plan["keyword_id"]
      return nil unless plan["query"] && plan["country"] && plan["language"]

      Keyword.find_by(query: plan["query"], engine: "google", country: plan["country"], language: plan["language"],
                      location: plan["location"], target_domain: plan["target_domain"])
    end

    def top_candidates(classification)
      classification.probabilities.sort_by { |_, probability| -probability }.first(2)
                    .map { |intent, probability| { intent: intent, probability: probability.round(4) } }
    end

    def prefill(extraction)
      { query: extraction.query, country: extraction.country, language: extraction.language,
        target_domain: extraction.target_domain }.compact
    end

    def base_analysis(classification)
      {
        classification: {
          intent: classification.intent,
          confidence: classification.confidence.round(4),
          probabilities: classification.probabilities.transform_values { |value| value.round(4) },
          min_confidence: @min_confidence
        }
      }
    end

    def unavailable(reason, extraction)
      Outcome.new(status: "unavailable", reason: reason, plan: nil, classification: nil,
                  analysis: { prefill: prefill(extraction), query_suggestions: extraction.query_candidates })
    end

    def record(text, outcome, duration_ms)
      classification = outcome.classification
      request = IntentRequest.create!(
        original_text: text,
        classifier_version: classification ? "laya:#{classification.model}@#{Config.version_label}" : nil,
        plan: outcome.plan,
        outcome: outcome.status,
        duration_ms: duration_ms,
        fallback_reason: outcome.reason,
        analysis: outcome.analysis.deep_stringify_keys.merge("laya_latency_ms" => classification&.latency_ms).compact
      )
      log(request, classification)
      request
    end

    # Structured line for log search. The sentence itself is deliberately not logged.
    def log(request, classification)
      Rails.logger.info(
        "intent_plan request_id=#{request.id} outcome=#{request.outcome} intent=#{classification&.intent || '-'} " \
        "confidence=#{classification ? classification.confidence.round(3) : '-'} reason=#{request.fallback_reason || '-'} " \
        "laya_ms=#{classification&.latency_ms || '-'} total_ms=#{request.duration_ms}"
      )
    end

    def monotonic_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
    end
  end
end
