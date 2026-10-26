module SearchOpsBenchmark
  # Runs every job right away in the calling thread, including retries that production would
  # schedule for later. The delay a retry WOULD have waited is recorded, not slept, so the
  # report can show the latency with and without that waiting.
  class ImmediateQueueAdapter
    attr_reader :delays

    def initialize
      @delays = []
    end

    def enqueue(job)
      ActiveJob::Base.execute(job.serialize)
    end

    def enqueue_at(job, timestamp)
      @delays << [ timestamp - Time.now.to_f, 0.0 ].max
      ActiveJob::Base.execute(job.serialize)
    end
  end
end
