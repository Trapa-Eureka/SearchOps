module Api
  module V1
    # Recent search runs across all keywords, newest first: the data behind a request timeline.
    # Without result bodies. A single run with its results is under /keywords/:id/searches/:id.
    class RunsController < BaseController
      def index
        scope = SearchRun.includes(:keyword, :rank_snapshot, :source_run).order(created_at: :desc, id: :desc)
        scope = scope.where(status: params[:status]) if SearchRun::STATUSES.include?(params[:status])
        scope = scope.where(error_category: params[:error_category]) if SearchRun::ERROR_CATEGORIES.include?(params[:error_category])
        scope = scope.where(keyword_id: params[:keyword_id]) if params[:keyword_id].to_s.match?(/\A\d+\z/)

        runs, meta = paginate(scope)
        data = runs.map do |run|
          SearchRunSerializer.call(run).merge(
            keyword: run.keyword.slice(:id, :query, :country, :language, :target_domain).symbolize_keys
          )
        end

        render json: { data: data, meta: meta }
      end
    end
  end
end
