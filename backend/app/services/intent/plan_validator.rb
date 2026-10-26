module Intent
  # Strict, server-side validation of a proposed plan. The proposal may come from Laya plus the
  # extractor, or from a client editing a plan before confirming; both go through here.
  #
  # Unknown fields are rejected (not ignored), every value must come from an allow-list or pass
  # the same rules as a Keyword, and there is no field that could express a destructive action.
  class PlanValidator
    Result = Data.define(:plan, :errors, :missing) do
      def valid?
        errors.empty? && missing.empty?
      end
    end

    # Fields an intent needs before it can run.
    REQUIRED = {
      "organic_rank_tracking" => %w[query country language target_domain],
      "job_search" => %w[query country language],
      "search_history" => []
    }.freeze

    def self.call(proposed)
      new(proposed).call
    end

    def initialize(proposed)
      @proposed = proposed.is_a?(Hash) ? proposed.stringify_keys : nil
      @errors = {}
    end

    def call
      return Result.new(plan: {}, errors: { "plan" => "must_be_an_object" }, missing: []) if @proposed.nil?

      unknown = @proposed.keys - Catalog::PLAN_FIELDS
      unknown.each { |field| @errors[field] = "unknown_field" }

      intent = @proposed["intent"]
      unless Catalog::INTENTS.include?(intent)
        @errors["intent"] = "not_allowed"
        return Result.new(plan: {}, errors: @errors, missing: [])
      end
      return Result.new(plan: { "intent" => "unsupported" }, errors: @errors, missing: []) if intent == "unsupported"

      plan = { "intent" => intent, "engine" => engine_for(intent) }
      plan["query"] = query
      plan["country"] = pick("country", Keyword::COUNTRIES)
      plan["language"] = pick("language", Keyword::LANGUAGES)
      plan["location"] = location
      plan["target_domain"] = target_domain
      plan["keyword_id"] = keyword_id
      plan["compare_previous"] = flag("compare_previous")
      plan["only_new"] = flag("only_new")

      Result.new(plan: plan.compact, errors: @errors, missing: missing_for(intent, plan))
    end

    private

    # The engine is derived from the intent. A proposal that names a different one is rejected.
    def engine_for(intent)
      expected = Catalog::ENGINES.fetch(intent)
      given = @proposed["engine"]
      @errors["engine"] = "does_not_match_intent" if given.present? && given != expected
      expected
    end

    def query
      value = @proposed["query"]
      return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
      return error("query", "must_be_text") unless value.is_a?(String)

      text = value.squish
      return error("query", "too_long") if text.length > Keyword::QUERY_MAX_LENGTH
      return error("query", "has_control_characters") if text.match?(/[[:cntrl:]]/)

      text
    end

    def pick(field, allowed)
      value = @proposed[field]
      return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
      return error(field, "must_be_text") unless value.is_a?(String)

      normalized = value.strip.downcase
      allowed.include?(normalized) ? normalized : error(field, "not_allowed")
    end

    def location
      value = @proposed["location"]
      return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
      return error("location", "must_be_text") unless value.is_a?(String)

      text = value.squish
      return error("location", "too_long") if text.length > Keyword::LOCATION_MAX_LENGTH
      return error("location", "has_control_characters") if text.match?(/[[:cntrl:]]/)

      text
    end

    def target_domain
      value = @proposed["target_domain"]
      return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
      return error("target_domain", "must_be_text") unless value.is_a?(String)

      DomainNormalizer.call(value) || error("target_domain", "not_a_domain")
    end

    def keyword_id
      value = @proposed["keyword_id"]
      return nil if value.nil?
      return error("keyword_id", "must_be_an_integer") unless value.is_a?(Integer)

      Keyword.exists?(value) ? value : error("keyword_id", "not_found")
    end

    # Only real booleans: the strings "true"/"false" or 1/0 are rejected so a loosely typed
    # value cannot slip through.
    def flag(field)
      value = @proposed[field]
      return false if value.nil?
      return value if [ true, false ].include?(value)

      error(field, "must_be_true_or_false")
      false
    end

    def missing_for(intent, plan)
      REQUIRED.fetch(intent).select { |field| plan[field].blank? && @errors[field].nil? }
    end

    def error(field, code)
      @errors[field] = code
      nil
    end
  end
end
