# Operational numbers for the dashboard and for debugging, from the runs table.
# Contains counts and timings only: never search terms, results, or credentials.
class MetricsSummary
  WINDOWS = { "1h" => 1.hour, "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze
  DEFAULT_WINDOW = "24h"
  # Width of one bar of the time series for each window (12 to 30 bars).
  BUCKET_SECONDS = { "1h" => 5.minutes.to_i, "24h" => 1.hour.to_i, "7d" => 12.hours.to_i, "30d" => 1.day.to_i }.freeze
  # What happened to a request. The four outcomes add up to every run in the bucket.
  OUTCOMES = %w[succeeded cache_hit failed active].freeze

  class << self
    def call(window: DEFAULT_WINDOW, now: Time.current)
      from = now - WINDOWS.fetch(window)
      runs = SearchRun.where(created_at: from..now)

      {
        window: { name: window, from: from, to: now },
        requests: requests(runs),
        series: series(runs, from, window),
        upstream: upstream(runs.upstream),
        cache: cache(runs),
        errors: runs.where(status: "failed").group(:error_category).count,
        budget: budget,
        keywords: keywords(now),
        queue: queue(now),
        intent: intent(from, now)
      }
    end

    private

    # Every search request is one run: cache hits included.
    def requests(runs)
      by_status = runs.group(:status).count
      {
        total: runs.count,
        by_status: SearchRun::STATUSES.index_with { |status| by_status.fetch(status, 0) },
        by_trigger: SearchRun::TRIGGERS.index_with { |trigger| runs.where(triggered_by: trigger).count }
      }
    end

    # Requests per time slice, split by outcome, oldest first. Slices with no requests are
    # included (all zeros) so a chart shows quiet periods as gaps instead of skipping them.
    # A run counts in the slice of its creation time. succeeded = answered by SerpApi,
    # cache_hit = answered from the local cache, active = still queued or running.
    def series(runs, from, window)
      size = BUCKET_SECONDS.fetch(window)
      count = WINDOWS.fetch(window).to_i / size
      slot = ActiveRecord::Base.sanitize_sql_array(
        [ "LEAST(FLOOR(EXTRACT(EPOCH FROM (created_at - ?::timestamptz)) / ?)::int, ?)", from, size, count - 1 ]
      )
      outcome = "CASE WHEN status = 'failed' THEN 'failed' WHEN status IN ('queued', 'running') THEN 'active' " \
                "WHEN cache_source = 'app' THEN 'cache_hit' ELSE 'succeeded' END"
      counts = runs.group(Arel.sql(slot), Arel.sql(outcome)).count

      buckets = Array.new(count) do |index|
        OUTCOMES.index_with { |name| counts.fetch([ index, name ], 0) }.merge(at: from + (index * size))
      end
      { bucket_seconds: size, buckets: buckets }
    end

    # Runs that went to SerpApi. Latency is the time of the last attempt of each run.
    def upstream(runs)
      succeeded = runs.where(status: "succeeded").count
      failed = runs.where(status: "failed").count
      finished = succeeded + failed
      count, p50, p95, max = runs.where.not(upstream_latency_ms: nil).pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY upstream_latency_ms)"),
        Arel.sql("percentile_cont(0.95) WITHIN GROUP (ORDER BY upstream_latency_ms)"),
        Arel.sql("MAX(upstream_latency_ms)")
      )

      {
        calls: runs.sum(:upstream_calls),
        retries: runs.sum("GREATEST(attempts - 1, 0)"),
        runs_succeeded: succeeded,
        runs_failed: failed,
        success_rate: finished.zero? ? nil : (succeeded.to_f / finished).round(4),
        latency_ms: { samples: count, p50: p50&.round, p95: p95&.round, max: max }
      }
    end

    # hit_rate = local cache hits / (hits + requests that really went upstream).
    # SerpApi's own cache cannot be observed (no documented response field).
    def cache(runs)
      hits = runs.where(cache_source: "app").count
      misses = runs.upstream.where("upstream_calls > 0").count
      total = hits + misses

      { hits: hits, misses: misses, hit_rate: total.zero? ? nil : (hits.to_f / total).round(4), ttl_seconds: SearchCache.ttl }
    end

    def budget
      { daily_limit: SearchBudget.daily_limit, used_today: SearchBudget.used_today, remaining_today: SearchBudget.remaining }
    end

    def keywords(now)
      all = Keyword.all.to_a
      freshness = KeywordFreshness.for(all, now: now).values

      {
        total: all.size,
        active: all.count(&:active),
        scheduled: all.count { |keyword| keyword.active && Keyword::SCHEDULE_INTERVALS.key?(keyword.schedule) },
        stale: freshness.count(&:stale?),
        no_data: freshness.count { |info| info.state == "no_data" }
      }
    end

    # Natural-language planning. Counts and timings only: the sentences are never included.
    def intent(from, now)
      requests = IntentRequest.where(created_at: from..now)
      by_outcome = requests.group(:outcome).count
      laya_ms = requests.where("analysis ? 'laya_latency_ms'").pluck(Arel.sql("(analysis->>'laya_latency_ms')::int")).sort

      {
        enabled: Intent::Config.enabled?,
        requests: requests.count,
        by_outcome: IntentRequest::OUTCOMES.index_with { |outcome| by_outcome.fetch(outcome, 0) },
        fallbacks: requests.where.not(fallback_reason: nil).group(:fallback_reason).count,
        laya_latency_ms: { samples: laya_ms.size, p50: percentile(laya_ms, 0.5), p95: percentile(laya_ms, 0.95), max: laya_ms.last }
      }
    end

    def percentile(sorted, fraction)
      return nil if sorted.empty?

      position = fraction * (sorted.size - 1)
      lower = sorted[position.floor]
      upper = sorted[position.ceil]
      (lower + ((upper - lower) * (position - position.floor))).round
    end

    # Job status as seen from the runs, plus whether any worker is alive to process them.
    def queue(now)
      active = SearchRun.active
      oldest = active.where(status: "queued").minimum(:updated_at)
      alive_since = now - (SolidQueue.respond_to?(:process_alive_threshold) ? SolidQueue.process_alive_threshold : 5.minutes)

      {
        queued: active.where(status: "queued").count,
        running: active.where(status: "running").count,
        oldest_queued_age_seconds: oldest && (now - oldest).round,
        workers_alive: SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", alive_since).count
      }
    end
  end
end
