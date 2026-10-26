class SearchRunSerializer
  PROVENANCE_FIELDS = %w[provider engine query country language location search_id].freeze

  # Pass includes(:rank_snapshot, :source_run) (and :search_results with include_results)
  # to avoid N+1 queries. A cache hit shows the results and rank of the run it was served from.
  def self.call(run, include_results: false)
    metadata = run.request_metadata
    source = run.results_run
    data = {
      id: run.id,
      keyword_id: run.keyword_id,
      status: run.status,
      triggered_by: run.triggered_by,
      started_at: run.started_at,
      finished_at: run.finished_at,
      attempts: run.attempts,
      upstream_calls: run.upstream_calls,
      upstream_latency_ms: run.upstream_latency_ms,
      http_status: run.http_status,
      error_category: run.error_category,
      error_message: metadata["error_message"],
      attempt_log: metadata["attempt_log"] || [],
      cache_source: run.cache_source,
      cache: { hit: run.cache_hit?, source_run_id: run.source_run_id, age_seconds: metadata["cache_age_seconds"] },
      result_count: metadata["result_count"],
      empty_results: metadata["empty_results"],
      request: metadata.slice(*PROVENANCE_FIELDS),
      rank: rank_summary(source.rank_snapshot),
      created_at: run.created_at
    }
    data[:results] = source.search_results.sort_by(&:position).map { |result| SearchResultSerializer.call(result) } if include_results
    data
  end

  def self.rank_summary(snapshot)
    return nil if snapshot.nil?

    { target_domain: snapshot.target_domain, rank: snapshot.rank, found: snapshot.found? }
  end
  private_class_method :rank_summary
end
