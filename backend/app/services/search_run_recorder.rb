# Writes the outcome of a run. Kept apart from the code that talks to the provider so
# the executor, the job (retry or final failure), and the reaper all record outcomes
# the same way.
class SearchRunRecorder
  # Entries kept in request_metadata["attempt_log"]. Enough to see why retries happened.
  ATTEMPT_LOG_LIMIT = 5

  def success(run, keyword, response, latency_ms)
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
        status: "succeeded", finished_at: finished_at, upstream_latency_ms: latency_ms, http_status: 200,
        error_category: nil,
        request_metadata: run.request_metadata.merge(
          "search_id" => response.search_id,
          "result_count" => response.results.size,
          "empty_results" => response.empty,
          "skipped_results" => response.skipped_count
        )
      )
    end
  end

  # Final failure. The last successful run and its snapshot are left untouched.
  def failure(run, error, latency_ms = nil)
    # A rolled-back transaction leaves its records in the association cache, and
    # saving the run would autosave (re-insert) them. Reload to drop that state.
    run.reload
    run.update!(
      status: "failed", finished_at: Time.current,
      upstream_latency_ms: latency_ms || run.upstream_latency_ms,
      http_status: error.http_status, error_category: error.category.to_s,
      request_metadata: with_attempt(run, error).merge("error_message" => error.message.first(300))
    )
  end

  # A transient failure that will be tried again: back to queued, not finished.
  def retry_later(run, error, latency_ms, delay_seconds)
    run.reload
    run.update!(
      status: "queued", upstream_latency_ms: latency_ms || run.upstream_latency_ms, http_status: error.http_status,
      request_metadata: with_attempt(run, error).merge("next_retry_in_seconds" => delay_seconds.round(1))
    )
  end

  private

  def with_attempt(run, error)
    entry = { "attempt" => run.attempts, "category" => error.category.to_s,
              "http_status" => error.http_status, "message" => error.message.first(120) }
    log = (run.request_metadata["attempt_log"] || []) + [ entry ]
    run.request_metadata.merge("attempt_log" => log.last(ATTEMPT_LOG_LIMIT))
  end
end
