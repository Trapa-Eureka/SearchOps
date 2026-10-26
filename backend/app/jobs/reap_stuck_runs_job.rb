# Recurring cleanup (see config/recurring.yml). A run that is "running" far longer than a
# request can take, or "queued" long after it should have been picked up, means a worker
# crashed or a job was lost. Close such runs as failed ("abandoned"): otherwise the
# one-active-run-per-keyword rule would block every future search for that keyword.
class ReapStuckRunsJob < ApplicationJob
  queue_as :default

  RUNNING_TIMEOUT = 10.minutes
  QUEUED_TIMEOUT = 30.minutes

  def perform
    recorder = SearchRunRecorder.new
    reaped = 0

    [ [ "running", RUNNING_TIMEOUT, "Worker stopped before finishing" ],
      [ "queued", QUEUED_TIMEOUT, "Not picked up by a worker" ] ].each do |status, timeout, message|
      SearchRun.where(status: status).where("updated_at < ?", timeout.ago).find_each do |run|
        recorder.failure(run, SearchProvider::Error.new(message, category: :abandoned))
        reaped += 1
      end
    end

    Rails.logger.info("reap_stuck_runs reaped=#{reaped}") if reaped.positive?
  end
end
