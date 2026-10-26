# What a keyword list needs to show at a glance, for any number of keywords in a fixed
# number of queries: the latest runs (oldest first, for a small bar strip) and where the
# target domain stands now compared with the snapshot before it.
#
# Latency percentiles here cover only the runs in the strip (RECENT_RUNS), not all time.
class KeywordActivity
  RECENT_RUNS = 20

  Info = Data.define(:recent_runs, :latency_ms, :rank)

  class << self
    # Returns { keyword_id => Info }.
    def for(keywords)
      keywords = Array(keywords)
      return {} if keywords.empty?

      ids = keywords.map(&:id)
      runs = recent_runs(ids)
      ranks = latest_ranks(ids)

      ids.to_h do |id|
        list = runs.fetch(id, [])
        [ id, Info.new(recent_runs: list, latency_ms: latency(list), rank: ranks[id]) ]
      end
    end

    private

    def recent_runs(ids)
      ranked = SearchRun.where(keyword_id: ids).select(
        :id, :keyword_id, :status, :cache_source, :error_category, :upstream_latency_ms, :attempts, :created_at,
        "ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY created_at DESC, id DESC) AS position"
      )
      SearchRun.from(ranked, :search_runs).where("position <= ?", RECENT_RUNS).order(:keyword_id, :created_at, :id)
               .group_by(&:keyword_id).transform_values { |runs| runs.map { |run| run_json(run) } }
    end

    def run_json(run)
      {
        id: run.id,
        status: run.status,
        cache_hit: run.cache_source == "app",
        error_category: run.error_category,
        latency_ms: run.upstream_latency_ms,
        retried: run.attempts > 1,
        created_at: run.created_at
      }
    end

    # Samples are the runs that really called SerpApi and recorded a latency.
    def latency(list)
      values = list.reject { |run| run[:cache_hit] }.filter_map { |run| run[:latency_ms] }.sort
      { samples: values.size, p95: percentile(values, 0.95), max: values.last }
    end

    def percentile(sorted, fraction)
      return nil if sorted.empty?

      position = fraction * (sorted.size - 1)
      lower = sorted[position.floor]
      upper = sorted[position.ceil]
      (lower + ((upper - lower) * (position - position.floor))).round
    end

    # The newest two snapshots per keyword, compared the way the rank history compares them.
    def latest_ranks(ids)
      ranked = RankSnapshot.where(keyword_id: ids).select(
        "rank_snapshots.*", "ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY captured_at DESC, id DESC) AS position"
      )
      RankSnapshot.from(ranked, :rank_snapshots).where("position <= 2").order(:keyword_id, captured_at: :desc, id: :desc)
                  .preload(:search_run).group_by(&:keyword_id).transform_values do |(current, previous)|
        comparison = RankComparison.between(previous: previous, current: current)
        RankSnapshotSerializer.call(current, comparison).slice(:rank, :found, :captured_at, :target_domain, :comparison)
      end
    end
  end
end
