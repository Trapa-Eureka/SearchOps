module Intent
  # Carries out a confirmed plan through the normal Rails path (Keyword + SearchEnqueuer), never
  # through the classifier. The client may edit the editable fields first; the result is validated
  # again from scratch, so a tampered or stale plan cannot reach the search code.
  #
  # Confirming twice returns the first result instead of searching twice.
  class Executor
    class NotConfirmable < StandardError
      attr_reader :code

      def initialize(code)
        super(code)
        @code = code
      end
    end

    class InvalidPlan < StandardError
      attr_reader :errors, :missing

      def initialize(errors:, missing: [])
        super("plan is not valid")
        @errors = errors
        @missing = missing
      end
    end

    # Raises NotConfirmable, InvalidPlan, SearchBudget::Exceeded.
    def call(intent_request, edits = {})
      intent_request.with_lock do
        return intent_request if intent_request.outcome == "executed"

        base = confirmable_plan(intent_request)
        plan = validated(merge_edits(base, edits))
        execution = execute(plan)

        intent_request.update!(outcome: "executed", plan: plan, confirmed_at: Time.current, execution: execution)
        Rails.logger.info("intent_confirmed request_id=#{intent_request.id} kind=#{execution['kind']} keyword_id=#{execution['keyword_id'] || '-'}")
      end
      intent_request
    end

    private

    # Only plans that understood the intent can be completed. A low-confidence or unsupported
    # request has no plan to confirm: the client must ask again or use the structured form.
    def confirmable_plan(intent_request)
      plan = intent_request.plan
      raise NotConfirmable, "no_plan_to_confirm" if plan.blank?
      raise NotConfirmable, "engine_not_available" if intent_request.fallback_reason == "engine_not_available"
      raise NotConfirmable, "not_confirmable" unless %w[planned needs_clarification].include?(intent_request.outcome)

      plan
    end

    def merge_edits(plan, edits)
      edits = edits.respond_to?(:to_unsafe_h) ? edits.to_unsafe_h : edits
      raise InvalidPlan.new(errors: { "plan" => "must_be_an_object" }) unless edits.is_a?(Hash)

      edits = edits.stringify_keys
      if edits.key?("intent") && edits["intent"] != plan["intent"]
        raise InvalidPlan.new(errors: { "intent" => "cannot_be_changed" })
      end

      plan.merge(edits)
    end

    def validated(proposed)
      result = PlanValidator.call(proposed)
      raise InvalidPlan.new(errors: result.errors, missing: result.missing) unless result.valid?
      raise NotConfirmable, "engine_not_available" if Keyword::ENGINES.exclude?(result.plan["engine"])

      result.plan
    end

    def execute(plan)
      case plan["intent"]
      when "organic_rank_tracking" then track_rank(plan)
      when "search_history" then { "kind" => "history", "keyword_id" => plan["keyword_id"] }
      else raise NotConfirmable, "not_confirmable"
      end
    end

    def track_rank(plan)
      keyword = Keyword.find_or_initialize_by(
        query: plan["query"], engine: plan["engine"], country: plan["country"], language: plan["language"],
        location: plan["location"], target_domain: plan["target_domain"]
      )
      created = keyword.new_record?
      unless keyword.save
        raise InvalidPlan.new(errors: keyword.errors.to_hash.to_h { |field, messages| [ field.to_s, messages.first ] })
      end

      result = SearchEnqueuer.new.call(keyword)
      { "kind" => "search", "keyword_id" => keyword.id, "keyword_created" => created, "run_id" => result.run.id,
        "search_outcome" => result.outcome.to_s }
    end
  end
end
