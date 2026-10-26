class KeywordSerializer
  FIELDS = %i[id query engine country language location target_domain active schedule created_at updated_at].freeze

  # freshness is a KeywordFreshness::Info. Compute it for a whole page with
  # KeywordFreshness.for(keywords) to avoid one query per keyword.
  def self.call(keyword, freshness = nil)
    data = keyword.as_json(only: FIELDS)
    data["freshness"] = freshness_json(freshness) if freshness
    data
  end

  def self.freshness_json(info)
    {
      state: info.state,
      reason: info.reason,
      last_success_at: info.last_success_at,
      last_attempt_status: info.last_attempt_status,
      last_attempt_at: info.last_attempt_at
    }
  end
end
