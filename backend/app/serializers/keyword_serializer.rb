class KeywordSerializer
  FIELDS = %i[id query engine country language location target_domain active schedule created_at updated_at].freeze

  def self.call(keyword)
    keyword.as_json(only: FIELDS)
  end
end
