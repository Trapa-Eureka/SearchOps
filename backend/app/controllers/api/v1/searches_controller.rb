module Api
  module V1
    class SearchesController < BaseController
      before_action :set_keyword

      rescue_from SearchProvider::NotConfigured, with: :render_not_configured
      rescue_from SearchBudget::Exceeded, with: :render_budget_exceeded

      def index
        scope = @keyword.search_runs.includes(:rank_snapshot).order(created_at: :desc, id: :desc)
        runs, meta = paginate(scope)

        render json: { data: runs.map { |run| SearchRunSerializer.call(run) }, meta: meta }
      end

      def show
        run = @keyword.search_runs.includes(:rank_snapshot, :search_results).find(params[:id])

        render json: { data: SearchRunSerializer.call(run, include_results: true) }
      end

      # Runs the search synchronously. Stage 4 moves this into a background job.
      def create
        orchestrator = SearchOrchestrator.new(provider: Providers::SerpApiSearchProvider.from_env)
        run = orchestrator.call(@keyword)

        if run.status == "succeeded"
          render json: { data: SearchRunSerializer.call(run, include_results: true) }, status: :created,
                 location: api_v1_keyword_search_path(@keyword, run)
        else
          render_error(failure_status(run.error_category), "search_failed", "Search failed",
                       { category: run.error_category, run_id: run.id })
        end
      end

      private

      def set_keyword
        @keyword = Keyword.find(params[:keyword_id])
      end

      # The run is stored either way; the HTTP status tells monitors what kind of failure it was.
      def failure_status(category)
        case category
        when "timeout" then :gateway_timeout
        when "quota", "rate_limit" then :too_many_requests
        else :bad_gateway
        end
      end

      def render_not_configured(_error)
        render_error(:service_unavailable, "search_provider_not_configured", "The search provider is not configured")
      end

      def render_budget_exceeded(error)
        render_error(:too_many_requests, "search_budget_exceeded", "Daily search budget reached",
                     { limit: error.limit, used: error.used })
      end
    end
  end
end
