# Performs ONE upstream attempt for a queued run. Deciding what happens next (retry,
# give up) belongs to ExecuteSearchJob. Laya is never involved: this path is deterministic.
#
# Safe to call twice for the same run (at-least-once job delivery): the run is claimed with
# a conditional update, so only one caller proceeds and the other gets :skipped.
class SearchOrchestrator
  # status: :succeeded, :failed (error is set, run left "running"), or :skipped
  Attempt = Data.define(:status, :error, :latency_ms)

  def initialize(provider:, budget: SearchBudget, recorder: SearchRunRecorder.new)
    @provider = provider
    @budget = budget
    @recorder = recorder
  end

  # Raises SearchBudget::Exceeded before anything is sent when the budget is spent.
  def execute(run)
    return skipped unless run.reload.status == "queued"

    @budget.check!(exclude_run: run)
    return skipped unless claim(run)

    keyword = run.keyword
    request = SearchProvider::Request.from_keyword(keyword)
    started = monotonic_ms

    begin
      response = @provider.search(request)
      latency = monotonic_ms - started
      @recorder.success(run, keyword, response, latency)
      log(run, "succeeded", latency)
      Attempt.new(status: :succeeded, error: nil, latency_ms: latency)
    rescue SearchProvider::Error => error
      latency = monotonic_ms - started
      log(run, "failed", latency, error)
      Attempt.new(status: :failed, error: error, latency_ms: latency)
    rescue ActiveRecord::RecordInvalid => error
      # Provider output that our own validations reject is a schema problem, not a crash.
      schema_error = SearchProvider::Error.new(
        "Result failed validation: #{error.record.errors.full_messages.to_sentence}", category: :schema, http_status: 200
      )
      latency = monotonic_ms - started
      log(run, "failed", latency, schema_error)
      Attempt.new(status: :failed, error: schema_error, latency_ms: latency)
    rescue StandardError => error
      # Never leave a run stuck in "running" if something unexpected breaks.
      @recorder.failure(run, SearchProvider::Error.new("Unexpected #{error.class}", category: :unknown), monotonic_ms - started)
      raise
    end
  end

  private

  def skipped
    Attempt.new(status: :skipped, error: nil, latency_ms: nil)
  end

  # Atomic claim: only one worker can move a run from queued to running.
  def claim(run)
    now = Time.current
    claimed = SearchRun.where(id: run.id, status: "queued").update_all(
      [ "status = 'running', attempts = attempts + 1, upstream_calls = upstream_calls + 1, " \
        "started_at = COALESCE(started_at, ?), updated_at = ?", now, now ]
    )
    run.reload if claimed.positive?
    claimed.positive?
  end

  # Structured line for log search. The query text and credentials are deliberately omitted.
  def log(run, outcome, latency_ms, error = nil)
    Rails.logger.info(
      "search_attempt run_id=#{run.id} keyword_id=#{run.keyword_id} attempt=#{run.attempts} outcome=#{outcome} " \
      "error_category=#{error&.category || '-'} http_status=#{error&.http_status || '-'} latency_ms=#{latency_ms}"
    )
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
  end
end
