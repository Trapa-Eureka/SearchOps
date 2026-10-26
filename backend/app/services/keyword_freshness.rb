# Whether the data shown for a keyword is current, so the UI can mark stale data visibly
# instead of silently showing an old rank.
#
#   no_data  no successful upstream search yet
#   stale    the newest finished attempt failed (the last good snapshot is still shown,
#            but it is older than the latest attempt), or the last success is older than
#            1.5 schedule intervals (Keyword::STALE_AFTER)
#   fresh    otherwise
#
# Cache hits are ignored: they carry no new data. "manual" keywords are never overdue.
class KeywordFreshness
  Info = Data.define(:state, :reason, :last_success_at, :last_attempt_status, :last_attempt_at) do
    def stale?
      state == "stale"
    end
  end

  class << self
    # Returns { keyword_id => Info } using two queries for any number of keywords.
    def for(keywords, now: Time.current)
      keywords = Array(keywords)
      return {} if keywords.empty?

      ids = keywords.map(&:id)
      last_success = SearchRun.upstream.where(keyword_id: ids, status: "succeeded").group(:keyword_id).maximum(:finished_at)
      last_attempt = SearchRun.upstream.finished.where(keyword_id: ids)
                              .select("DISTINCT ON (keyword_id) keyword_id, status, finished_at")
                              .order("keyword_id, finished_at DESC, id DESC").index_by(&:keyword_id)

      keywords.to_h { |keyword| [ keyword.id, build(keyword, last_success[keyword.id], last_attempt[keyword.id], now) ] }
    end

    private

    def build(keyword, success_at, attempt, now)
      state, reason =
        if success_at.nil?
          [ "no_data", nil ]
        elsif attempt&.status == "failed"
          [ "stale", "last_attempt_failed" ]
        elsif (limit = Keyword::STALE_AFTER[keyword.schedule]) && success_at < now - limit
          [ "stale", "overdue" ]
        else
          [ "fresh", nil ]
        end

      Info.new(state: state, reason: reason, last_success_at: success_at,
               last_attempt_status: attempt&.status, last_attempt_at: attempt&.finished_at)
    end
  end
end
