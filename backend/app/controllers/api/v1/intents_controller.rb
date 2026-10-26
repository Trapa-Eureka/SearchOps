module Api
  module V1
    # Natural-language planning. The classifier proposes, Rails validates, and nothing runs until
    # the client confirms. With LAYA_ENABLED=false (the default) every call still answers, with a
    # structured-input fallback, and the keyword/search API is untouched.
    class IntentsController < BaseController
      PLAN_LIMIT = 30
      RATE_STORE = ActiveSupport::Cache::MemoryStore.new

      # Per client IP. A process-local store: enough for one server, replace for several.
      rate_limit to: PLAN_LIMIT, within: 1.minute, only: :plan, store: RATE_STORE,
                 with: -> { render_error(:too_many_requests, "rate_limited", "Too many planning requests, try again shortly") }

      rescue_from Intent::Planner::Rejected, with: :render_invalid_text
      rescue_from Intent::Executor::NotConfirmable, with: :render_not_confirmable
      rescue_from Intent::Executor::InvalidPlan, with: :render_invalid_plan
      rescue_from SearchBudget::Exceeded, with: :render_budget_exceeded
      rescue_from SearchProvider::NotConfigured, with: :render_not_configured

      # POST /api/v1/intent/plan  { "text": "..." }
      def plan
        request_record = Intent::Planner.new.call(params[:text])

        render json: { data: IntentRequestSerializer.call(request_record) }, status: :created,
               location: "/api/v1/intent/plan/#{request_record.id}"
      end

      # GET /api/v1/intent/plan/:id
      def show
        render json: { data: IntentRequestSerializer.call(IntentRequest.find(params[:id])) }
      end

      # POST /api/v1/intent/plan/:id/confirm  { "plan": { ...edits to editable fields... } }
      def confirm
        request_record = IntentRequest.find(params[:id])
        if request_record.outcome != "executed" && request_record.plan&.dig("intent") == "organic_rank_tracking" &&
           !Providers::SerpApiSearchProvider.configured?
          raise SearchProvider::NotConfigured, "SERPAPI_API_KEY is not configured"
        end

        Intent::Executor.new.call(request_record, edits)
        render json: { data: IntentRequestSerializer.call(request_record.reload) }
      end

      private

      def edits
        value = params[:plan]
        return {} if value.nil?
        raise Intent::Executor::InvalidPlan.new(errors: { "plan" => "must_be_an_object" }) unless value.respond_to?(:to_unsafe_h)

        value.to_unsafe_h
      end

      def render_invalid_text(error)
        render_error(:unprocessable_content, "invalid_text", "The text cannot be used", { text: error.code })
      end

      def render_not_confirmable(error)
        render_error(:unprocessable_content, "not_confirmable", "This request cannot be confirmed", { reason: error.code })
      end

      def render_invalid_plan(error)
        render_error(:unprocessable_content, "invalid_plan", "The plan is not valid", { errors: error.errors, missing: error.missing })
      end

      def render_budget_exceeded(error)
        render_error(:too_many_requests, "search_budget_exceeded", "Daily search budget reached", { limit: error.limit, used: error.used })
      end

      def render_not_configured(_error)
        render_error(:service_unavailable, "search_provider_not_configured", "The search provider is not configured")
      end
    end
  end
end
