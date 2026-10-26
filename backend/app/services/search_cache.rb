# Local result cache. There is no separate store: a recent successful run IS the cache
# entry. A hit is recorded as its own SearchRun (cache_source "app") pointing at the run
# it was served from, so hits are counted exactly and never touch SerpApi or the budget.
#
# This is independent of SerpApi's own cache (identical request within an hour is free
# on their side). SerpApi documents no response field that says a result came from that
# cache, so it cannot be observed and is not tracked.
class SearchCache
  DEFAULT_TTL_SECONDS = 3600
  MAX_TTL_SECONDS = 86_400

  class << self
    # 0 disables the cache. An unreadable value falls back to the default rather than
    # disabling it silently (a disabled cache would raise API usage).
    def ttl
      value = Integer(ENV.fetch("SEARCH_CACHE_TTL_SECONDS", DEFAULT_TTL_SECONDS).to_s, 10, exception: false)
      value.nil? ? DEFAULT_TTL_SECONDS : value.clamp(0, MAX_TTL_SECONDS)
    end

    # The newest successful upstream run for the same keyword and search settings that is
    # still within the TTL, or nil. It must carry a snapshot for the keyword's current
    # target domain, because a cache hit does not create a new snapshot.
    def lookup(keyword:, fingerprint:, now: Time.current)
      return nil if ttl.zero?

      candidate = keyword.search_runs.upstream
                         .where(fingerprint: fingerprint, status: "succeeded")
                         .where(finished_at: (now - ttl)..now)
                         .order(finished_at: :desc, id: :desc)
                         .includes(:rank_snapshot)
                         .first
      return nil if candidate.nil?
      return candidate if keyword.target_domain.blank?

      candidate if candidate.rank_snapshot&.target_domain == keyword.target_domain
    end
  end
end
