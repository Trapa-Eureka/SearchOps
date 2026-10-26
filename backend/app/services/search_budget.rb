# Daily cap on requests sent to SerpApi, so a script, a retry storm, or a bug cannot
# burn the account quota.
#
# Counts real upstream calls (retries included), plus one reserved call for every
# queued run that has not been tried yet. Cache hits cost nothing. The real account
# quota must be read from SerpApi's Account API (`rake searchops:serpapi_quota`); this
# is only a local guard. The count is not atomic, so simultaneous requests can overshoot.
class SearchBudget
  DEFAULT_DAILY_LIMIT = 5

  class Exceeded < StandardError
    attr_reader :limit, :used

    def initialize(limit:, used:)
      @limit = limit
      @used = used
      super("daily search budget reached (#{used}/#{limit})")
    end
  end

  class << self
    # Fails closed: a non-numeric value becomes 0 and blocks all searches.
    def daily_limit
      Integer(ENV.fetch("SEARCH_MAX_REQUESTS_PER_DAY", DEFAULT_DAILY_LIMIT).to_s, 10, exception: false) || 0
    end

    # exclude_run: a run checking its own budget must not count its own reservation.
    def used_today(exclude_run: nil)
      today = SearchRun.where(created_at: Time.current.all_day)
      reserved = today.active.where(upstream_calls: 0)
      reserved = reserved.where.not(id: exclude_run.id) if exclude_run
      today.sum(:upstream_calls) + reserved.count
    end

    def remaining(exclude_run: nil)
      [ daily_limit - used_today(exclude_run: exclude_run), 0 ].max
    end

    def check!(exclude_run: nil)
      limit = daily_limit
      used = used_today(exclude_run: exclude_run)
      raise Exceeded.new(limit: limit, used: used) if used >= limit
    end
  end
end
