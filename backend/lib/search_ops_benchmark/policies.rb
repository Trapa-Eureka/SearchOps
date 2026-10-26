module SearchOpsBenchmark
  # What the simulated person does with the answer to a sentence. A decision is
  # [:confirm, edits_or_nil], [:structured] (give up on the sentence and use the keyword form),
  # or [:stop] (nothing more to do).
  module Policies
    FIELDS = %w[query country language target_domain].freeze

    module_function

    def normalize(value)
      value.to_s.downcase.squish
    end

    def plan_matches_task?(plan, task)
      plan.present? && plan["intent"] == "organic_rank_tracking" && FIELDS.all? { |field| normalize(plan[field]) == normalize(task[field]) }
    end

    # How many of the task's fields the plan lacks or has wrong: what the person has to type or fix.
    def edits_needed(plan, task)
      FIELDS.count { |field| normalize(plan&.dig(field)) != normalize(task[field]) }
    end

    # Reads the plan and only confirms what they meant. A sentence with missing details is
    # completed from what they had in mind; anything else goes to the keyword form.
    class Diligent
      def decide(item, body)
        task = item["task"]
        plan = body["plan"]
        status = body["status"]

        if task
          return [ :confirm, nil ] if status == "ready" && Policies.plan_matches_task?(plan, task)
          return [ :confirm, task.slice(*FIELDS) ] if status == "needs_clarification" && body["reason"] == "missing_fields" && plan&.dig("intent") == "organic_rank_tracking"

          [ :structured ]
        elsif status == "ready" && item["intent"] == "search_history" && plan&.dig("intent") == "search_history"
          [ :confirm, nil ]
        else
          [ :stop ]
        end
      end
    end

    # The worst case for cost: confirms every ready plan without reading it.
    class Careless
      def decide(_item, body)
        body["status"] == "ready" ? [ :confirm, nil ] : [ :stop ]
      end
    end
  end
end
