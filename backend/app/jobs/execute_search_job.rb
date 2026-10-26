# Runs one queued SearchRun against the provider, retrying transient failures.
#
# Idempotent: a run that is not "queued" (already running elsewhere, finished, or deleted)
# is ignored, so a duplicate delivery of the job is harmless. Retries are re-enqueued by
# this job itself with a computed delay, and only for errors where trying again can help
# (SearchProvider::Error#retryable?). Auth, quota, invalid requests, and schema problems
# fail immediately.
class ExecuteSearchJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 3

  # Bounds how many searches talk to SerpApi at once (shared across workers and processes).
  limits_concurrency to: Integer(ENV.fetch("SEARCH_MAX_CONCURRENCY", 2).to_s, 10, exception: false) || 2,
                     key: ->(_run_id) { "serpapi_search" },
                     duration: 5.minutes

  def perform(run_id)
    run = SearchRun.find_by(id: run_id)
    return if run.nil? || run.status != "queued"

    recorder = SearchRunRecorder.new
    provider = build_provider(run, recorder)
    return if provider.nil?

    attempt = SearchOrchestrator.new(provider: provider, recorder: recorder).execute(run)
    handle(run, attempt, recorder) if attempt.status == :failed
  rescue SearchBudget::Exceeded => error
    recorder.failure(run, SearchProvider::Error.new(error.message, category: :budget))
  end

  private

  def build_provider(run, recorder)
    Providers::SerpApiSearchProvider.from_env
  rescue SearchProvider::NotConfigured
    recorder.failure(run, SearchProvider::Error.new("SerpApi key is not configured", category: :auth))
    nil
  end

  def handle(run, attempt, recorder)
    error = attempt.error
    run.reload

    if error.retryable? && run.attempts < MAX_ATTEMPTS
      delay = RetryBackoff.delay(run.attempts, retry_after: error.retry_after)
      recorder.retry_later(run, error, attempt.latency_ms, delay)
      self.class.set(wait: delay.seconds).perform_later(run.id)
      Rails.logger.info("search_retry run_id=#{run.id} attempt=#{run.attempts} error_category=#{error.category} delay_seconds=#{delay.round(1)}")
    else
      recorder.failure(run, error, attempt.latency_ms)
      Rails.logger.info("search_failed run_id=#{run.id} attempts=#{run.attempts} error_category=#{error.category}")
    end
  end
end
