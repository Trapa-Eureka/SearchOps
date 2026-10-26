require "rails_helper"

RSpec.describe MetricsSummary, env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "20", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
  let(:summary) { described_class.call(window: "24h") }

  def run(*traits, **attrs)
    create(:search_run, *traits, **attrs)
  end

  describe "with no data" do
    it "reports zeros and nil rates instead of dividing by zero" do
      expect(summary[:requests]).to include(total: 0)
      expect(summary[:upstream]).to include(calls: 0, retries: 0, success_rate: nil)
      expect(summary[:upstream][:latency_ms]).to eq(samples: 0, p50: nil, p95: nil, max: nil)
      expect(summary[:cache]).to include(hits: 0, misses: 0, hit_rate: nil)
      expect(summary[:errors]).to eq({})
    end
  end

  describe "requests" do
    it "counts every run by status and trigger, cache hits included" do
      run
      run(triggered_by: "scheduled")
      run(status: "failed", error_category: "timeout")
      run(:queued)
      run(:running)
      run(:cache_hit)

      requests = summary[:requests]
      expect(requests[:total]).to eq(7) # the cache hit also creates its source run
      expect(requests[:by_status]).to eq("queued" => 1, "running" => 1, "succeeded" => 4, "failed" => 1)
      expect(requests[:by_trigger]).to eq("manual" => 6, "scheduled" => 1)
    end
  end

  describe "upstream" do
    it "computes success rate, calls, retries, and latency percentiles" do
      [ 100, 200, 300, 400 ].each { |ms| run(upstream_latency_ms: ms, upstream_calls: 1, attempts: 1) }
      run(status: "failed", error_category: "upstream", upstream_latency_ms: 500, upstream_calls: 3, attempts: 3)

      upstream = summary[:upstream]
      expect(upstream).to include(calls: 7, retries: 2, runs_succeeded: 4, runs_failed: 1, success_rate: 0.8)
      expect(upstream[:latency_ms]).to eq(samples: 5, p50: 300, p95: 480, max: 500)
    end

    it "excludes cache hits from the upstream numbers" do
      run(:cache_hit, upstream_latency_ms: 0)

      expect(summary[:upstream][:calls]).to eq(1) # only the source run
      expect(summary[:upstream][:latency_ms][:samples]).to eq(0)
    end

    it "ignores unfinished runs when computing the success rate" do
      run
      run(:queued)

      expect(summary[:upstream][:success_rate]).to eq(1.0)
    end
  end

  describe "cache" do
    it "computes the hit rate from local hits and requests that really went upstream" do
      source = run
      create_list(:search_run, 3, :cache_hit, source_run: source, keyword: source.keyword)

      cache = summary[:cache]
      expect(cache).to include(hits: 3, misses: 1, hit_rate: 0.75, ttl_seconds: 3600)
    end

    it "does not count runs that never reached the provider as misses" do
      run(:failed, upstream_calls: 0, error_category: "budget")
      run(:queued)

      expect(summary[:cache][:misses]).to eq(0)
    end
  end

  describe "errors" do
    it "counts failed runs by category" do
      run(:failed, error_category: "timeout")
      run(:failed, error_category: "timeout")
      run(:failed, error_category: "auth")
      run

      expect(summary[:errors]).to eq("timeout" => 2, "auth" => 1)
    end
  end

  describe "budget" do
    it "reports the limit, usage, and what is left" do
      run(upstream_calls: 3)

      expect(summary[:budget]).to eq(daily_limit: 20, used_today: 3, remaining_today: 17)
    end
  end

  describe "keywords" do
    it "counts keywords by activity, schedule, and freshness" do
      fresh = create(:keyword, schedule: "daily")
      create(:search_run, keyword: fresh)
      stale = create(:keyword, schedule: "manual")
      create(:search_run, keyword: stale, finished_at: 3.hours.ago)
      create(:search_run, :failed, keyword: stale, finished_at: 1.hour.ago)
      create(:keyword, active: false)

      expect(summary[:keywords]).to eq(total: 3, active: 2, scheduled: 1, stale: 1, no_data: 1)
    end
  end

  describe "queue" do
    it "reports waiting and running work, the oldest wait, and live workers" do
      queued = run(:queued)
      queued.update_columns(updated_at: 90.seconds.ago)
      run(:running)

      queue = summary[:queue]
      expect(queue).to include(queued: 1, running: 1, workers_alive: 0)
      expect(queue[:oldest_queued_age_seconds]).to be_between(89, 95)
    end

    it "counts only workers with a recent heartbeat" do
      now = Time.current
      SolidQueue::Process.create!(kind: "Worker", name: "alive", pid: 1, last_heartbeat_at: now)
      SolidQueue::Process.create!(kind: "Worker", name: "dead", pid: 2, last_heartbeat_at: 1.hour.ago)
      SolidQueue::Process.create!(kind: "Dispatcher", name: "not-a-worker", pid: 3, last_heartbeat_at: now)

      expect(summary[:queue][:workers_alive]).to eq(1)
    end

    it "has no oldest wait when nothing is queued" do
      expect(summary[:queue][:oldest_queued_age_seconds]).to be_nil
    end
  end

  describe "windows" do
    it "only includes runs created inside the window" do
      run(created_at: 2.hours.ago)
      run(created_at: 3.days.ago)
      run(created_at: 20.days.ago)

      expect(described_class.call(window: "1h")[:requests][:total]).to eq(0)
      expect(described_class.call(window: "24h")[:requests][:total]).to eq(1)
      expect(described_class.call(window: "7d")[:requests][:total]).to eq(2)
      expect(described_class.call(window: "30d")[:requests][:total]).to eq(3)
    end

    it "echoes the window it used" do
      result = described_class.call(window: "7d", now: Time.zone.parse("2026-10-26 12:00:00"))

      expect(result[:window]).to eq(name: "7d", from: Time.zone.parse("2026-10-19 12:00:00"), to: Time.zone.parse("2026-10-26 12:00:00"))
    end

    it "rejects an unknown window" do
      expect { described_class.call(window: "1y") }.to raise_error(KeyError)
    end
  end

  it "never contains search terms or secrets" do
    run(request_metadata: { "query" => "very private words", "error_message" => "Invalid API key sk-123" })

    expect(summary.to_json).not_to include("very private words")
    expect(summary.to_json).not_to include("sk-123")
  end
end
