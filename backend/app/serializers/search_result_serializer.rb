class SearchResultSerializer
  FIELDS = %i[position title url display_domain snippet].freeze

  def self.call(result)
    result.as_json(only: FIELDS)
  end
end
