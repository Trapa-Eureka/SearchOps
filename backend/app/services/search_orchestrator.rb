# Runs one search for a keyword and records what happened.
#
# Flow: check the daily budget, create a SearchRun, call the provider, then store
# the normalized results and (when the keyword has a target domain) a RankSnapshot.
# Provider failures are recorded on the run and returned, not raised, so the caller
# always gets a run to report. Laya is never involved: this path is deterministic.
#
# Stage 3 runs synchronously. Stage 4 moves execution into Active Job and adds
# caching, deduplication, and retries around this class.
class SearchOrchestrator
  def initialize(provider:, budget: SearchBudget)
    @provider = provider
    @budget = budget
  end

  # Returns the finished SearchRun (status "succeeded" or "failed").
  # Raises SearchBudget::Exceeded before anything is created or sent.
  def call(keyword)
    request = SearchProvider::Request.from_keyword(keyword)
    @budget.check!

    run = keyword.search_runs.create!(
      fingerprint: SearchFingerprint.call(request),
      status: "running",
      started_at: Time.current,
      request_metadata: provenance(request)
    )

    execute(run, keyword, request)
    log(run)
    run
  end

  private

  def execute(run, keyword, request)
    started = monotonic_ms
    begin
      response = @provider.search(request)
      latency = monotonic_ms - started
      record_success(run, keyword, response, latency)
    rescue SearchProvider::Error => error
      record_failure(run, error, monotonic_ms - started)
    rescue ActiveRecord::RecordInvalid => error
      # Provider output that our own validations reject is a schema problem, not a crash.
      schema_error = SearchProvider::Error.new("Result failed validation: #{error.record.errors.full_messages.to_sentence}",
                                               category: :schema, http_status: 200)
      record_failure(run, schema_error, monotonic_ms - started)
    rescue StandardError => error
      # Never leave a run stuck in "running" if something unexpected breaks.
      record_failure(run, SearchProvider::Error.new("Unexpected #{error.class}", category: :unknown), monotonic_ms - started)
      raise
    end
  end

  def record_success(run, keyword, response, latency)
    finished_at = Time.current

    # A savepoint, so a failure rolls back results and snapshot even when the
    # caller already holds a transaction.
    SearchRun.transaction(requires_new: true) do
      response.results.each do |result|
        run.search_results.create!(
          position: result.position, title: result.title, url: result.url,
          display_domain: result.display_domain, snippet: result.snippet, extra: result.extra
        )
      end

      if keyword.target_domain.present?
        RankSnapshot.create!(
          keyword: keyword, search_run: run, target_domain: keyword.target_domain,
          rank: RankCalculator.call(results: response.results, target_domain: keyword.target_domain),
          captured_at: finished_at
        )
      end

      run.update!(
        status: "succeeded", finished_at: finished_at, upstream_latency_ms: latency, http_status: 200,
        request_metadata: run.request_metadata.merge(
          "search_id" => response.search_id,
          "result_count" => response.results.size,
          "empty_results" => response.empty,
          "skipped_results" => response.skipped_count
        )
      )
    end
  end

  def record_failure(run, error, latency)
    # A rolled-back transaction leaves its records in the association cache, and
    # saving the run would autosave (re-insert) them. Reload to drop that state.
    run.reload
    run.update!(
      status: "failed", finished_at: Time.current, upstream_latency_ms: latency,
      http_status: error.http_status, error_category: error.category.to_s,
      request_metadata: run.request_metadata.merge("error_message" => error.message.first(300))
    )
  end

  # Enough to explain a ranking difference later: what was asked, of which provider.
  def provenance(request)
    {
      "provider" => "serpapi", "engine" => request.engine, "query" => request.query,
      "country" => request.country, "language" => request.language, "location" => request.location
    }
  end

  # Structured line for log search. The query text and credentials are deliberately omitted.
  def log(run)
    Rails.logger.info(
      "search_run run_id=#{run.id} keyword_id=#{run.keyword_id} status=#{run.status} " \
      "error_category=#{run.error_category || '-'} http_status=#{run.http_status || '-'} " \
      "latency_ms=#{run.upstream_latency_ms}"
    )
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
  end
end
