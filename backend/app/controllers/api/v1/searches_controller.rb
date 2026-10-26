module Api
  module V1
    class SearchesController < BaseController
      before_action :set_keyword

      rescue_from SearchProvider::NotConfigured, with: :render_not_configured
      rescue_from SearchBudget::Exceeded, with: :render_budget_exceeded

      def index
        scope = @keyword.search_runs.includes(:rank_snapshot, :source_run).order(created_at: :desc, id: :desc)
        runs, meta = paginate(scope)

        render json: { data: runs.map { |run| SearchRunSerializer.call(run) }, meta: meta }
      end

      def show
        run = @keyword.search_runs.includes(:rank_snapshot, :search_results, source_run: %i[rank_snapshot search_results]).find(params[:id])

        render json: { data: SearchRunSerializer.call(run, include_results: true) }
      end

      # Does not call SerpApi in the request. Outcomes (meta.outcome):
      #   cache_hit     200  answered from a recent run, results included
      #   enqueued      202  queued for a worker, poll GET .../searches/:id
      #   deduplicated  202  an identical run is already queued or running, returned as is
      # ?refresh=true skips the cache (still deduplicated and counted against the budget).
      def create
        raise SearchProvider::NotConfigured, "SERPAPI_API_KEY is not configured" unless Providers::SerpApiSearchProvider.configured?

        result = SearchEnqueuer.new.call(@keyword, refresh: refresh?)
        run = result.run
        done = run.status == "succeeded"

        render json: { data: SearchRunSerializer.call(run, include_results: done), meta: { outcome: result.outcome } },
               status: result.outcome == :cache_hit ? :ok : :accepted,
               location: api_v1_keyword_search_path(@keyword, run)
      end

      private

      def set_keyword
        @keyword = Keyword.find(params[:keyword_id])
      end

      def refresh?
        ActiveModel::Type::Boolean.new.cast(params[:refresh]) == true
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
