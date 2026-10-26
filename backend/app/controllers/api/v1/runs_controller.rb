module Api
  module V1
    # Recent search runs across all keywords, newest first: the data behind a request timeline.
    # Without result bodies. A single run with its results is under /keywords/:id/searches/:id.
    class RunsController < BaseController
      def index
        scope = SearchRun.includes(:keyword, :rank_snapshot, :source_run).order(created_at: :desc, id: :desc)
        scope = scope.where(error_category: params[:error_category]) if SearchRun::ERROR_CATEGORIES.include?(params[:error_category])
        scope = scope.where(keyword_id: params[:keyword_id]) if params[:keyword_id].to_s.match?(/\A\d+\z/)
        # Counted before the status filter, so tabs can show how many runs each status has.
        counts = scope.reorder(nil).group(:status).count
        scope = scope.where(status: params[:status]) if SearchRun::STATUSES.include?(params[:status])

        runs, meta = paginate(scope)
        data = runs.map do |run|
          SearchRunSerializer.call(run).merge(
            keyword: run.keyword.slice(:id, :query, :country, :language, :target_domain).symbolize_keys
          )
        end

        meta = meta.merge(counts: SearchRun::STATUSES.index_with { |status| counts.fetch(status, 0) }.merge("all" => counts.values.sum))
        render json: { data: data, meta: meta }
      end
    end
  end
end
