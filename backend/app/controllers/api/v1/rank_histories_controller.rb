module Api
  module V1
    # Rank of the keyword's target domain over time, newest first.
    # A smaller rank is a better position. A null rank means "not found in the
    # retrieved result window" (it is never 0). Each entry says how it moved
    # compared with the snapshot just before it, or that the two cannot be compared.
    class RankHistoriesController < BaseController
      def show
        keyword = Keyword.find(params[:keyword_id])
        scope = keyword.rank_snapshots.includes(:search_run).order(captured_at: :desc, id: :desc)

        snapshots, meta = paginate(scope)
        snapshots = snapshots.to_a
        # The snapshot just before the last one on this page, needed for its comparison.
        older = scope.offset(meta[:page] * meta[:per_page]).limit(1).to_a.first
        chain = snapshots + [ older ].compact

        data = snapshots.each_with_index.map do |snapshot, index|
          RankSnapshotSerializer.call(snapshot, RankComparison.between(previous: chain[index + 1], current: snapshot))
        end

        render json: {
          data: data,
          meta: meta.merge(
            target_domain: keyword.target_domain,
            ordering: "newest_first",
            rank_semantics: "lower_is_better",
            null_rank_meaning: "not_found_in_retrieved_window",
            freshness: KeywordSerializer.freshness_json(KeywordFreshness.for(keyword)[keyword.id])
          )
        }
      end
    end
  end
end
