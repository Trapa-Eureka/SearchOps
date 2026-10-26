class IntentRequestSerializer
  EXECUTABLE_INTENTS = %w[organic_rank_tracking search_history].freeze
  STRUCTURED_FIELDS = %w[query country language location target_domain].freeze

  def self.call(request)
    analysis = request.analysis
    plan = request.plan
    status = request.outcome == "planned" ? "ready" : request.outcome
    confirmable = plan.present? && EXECUTABLE_INTENTS.include?(plan["intent"]) && %w[planned needs_clarification].include?(request.outcome)

    {
      id: request.id,
      status: status,
      reason: request.fallback_reason,
      next_step: next_step(request, confirmable),
      plan: plan,
      requires_confirmation: plan.present? && plan["intent"] == "organic_rank_tracking",
      missing: analysis["missing"] || [],
      errors: analysis["errors"] || {},
      fields: analysis["fields"] || {},
      candidates: analysis["candidates"] || [],
      keyword_candidates: analysis["keyword_candidates"] || [],
      query_suggestions: analysis["query_suggestions"] || [],
      history: analysis["history"],
      notes: analysis["notes"] || [],
      classifier: classifier(request, analysis),
      structured_input: structured_input(request, analysis),
      execution: request.execution,
      created_at: request.created_at,
      confirmed_at: request.confirmed_at
    }
  end

  # What the client should do with this response.
  def self.next_step(request, confirmable)
    case request.outcome
    when "planned" then "confirm"
    when "executed" then "none"
    when "needs_clarification" then confirmable ? "complete_fields" : "rephrase_or_use_structured_input"
    when "unavailable" then "use_structured_input"
    else "none"
    end
  end
  private_class_method :next_step

  def self.classifier(request, analysis)
    classification = analysis["classification"]
    {
      name: "laya",
      enabled: classification.present? || request.fallback_reason != "laya_disabled",
      version: request.classifier_version,
      intent: classification&.dig("intent"),
      confidence: classification&.dig("confidence"),
      probabilities: classification&.dig("probabilities"),
      min_confidence: classification&.dig("min_confidence"),
      latency_ms: analysis["laya_latency_ms"]
    }.compact
  end
  private_class_method :classifier

  # The way to do the same thing without the classifier: the regular keyword API.
  def self.structured_input(request, analysis)
    return nil if %w[planned executed unsupported].include?(request.outcome)

    { endpoint: "/api/v1/keywords", fields: STRUCTURED_FIELDS, prefill: analysis["prefill"] || {} }
  end
  private_class_method :structured_input
end
