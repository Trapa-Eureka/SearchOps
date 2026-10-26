class SearchRunSerializer
  PROVENANCE_FIELDS = %w[provider engine query country language location search_id].freeze

  # Pass includes(:rank_snapshot) (and :search_results with include_results) to avoid N+1 queries.
  def self.call(run, include_results: false)
    metadata = run.request_metadata
    data = {
      id: run.id,
      keyword_id: run.keyword_id,
      status: run.status,
      started_at: run.started_at,
      finished_at: run.finished_at,
      upstream_latency_ms: run.upstream_latency_ms,
      http_status: run.http_status,
      error_category: run.error_category,
      error_message: metadata["error_message"],
      cache_source: run.cache_source,
      result_count: metadata["result_count"],
      empty_results: metadata["empty_results"],
      request: metadata.slice(*PROVENANCE_FIELDS),
      rank: rank_summary(run.rank_snapshot),
      created_at: run.created_at
    }
    data[:results] = run.search_results.sort_by(&:position).map { |result| SearchResultSerializer.call(result) } if include_results
    data
  end

  def self.rank_summary(snapshot)
    return nil if snapshot.nil?

    { target_domain: snapshot.target_domain, rank: snapshot.rank, found: snapshot.found? }
  end
  private_class_method :rank_summary
end
