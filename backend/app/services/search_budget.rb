# Daily cap on upstream searches, so a script or a bug cannot burn the SerpApi quota.
#
# Counts every run created today (UTC day) because each one is a billable request
# at most. The real account quota must be read from SerpApi's Account API; this is
# only a local guard. Concurrency limits and caching are added in Stage 4.
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

    def used_today
      SearchRun.where(created_at: Time.current.all_day).count
    end

    def check!
      limit = daily_limit
      used = used_today
      raise Exceeded.new(limit: limit, used: used) if used >= limit
    end
  end
end
