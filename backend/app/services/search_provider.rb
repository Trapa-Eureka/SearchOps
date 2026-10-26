# Contract between the orchestrator and any search backend.
#
# A provider responds to #search(SearchProvider::Request) and returns a
# SearchProvider::Response, or raises SearchProvider::Error with a category.
# Providers never touch the database and never decide retry policy.
module SearchProvider
  Request = Data.define(:query, :engine, :country, :language, :location) do
    def self.from_keyword(keyword)
      new(query: keyword.query, engine: keyword.engine, country: keyword.country,
          language: keyword.language, location: keyword.location)
    end
  end

  Result = Data.define(:position, :title, :url, :display_domain, :snippet, :extra)

  # empty is true when the provider answered successfully with zero usable results.
  Response = Data.define(:results, :empty, :search_id, :skipped_count)

  # Categories match SearchRun::ERROR_CATEGORIES.
  class Error < StandardError
    RETRYABLE_CATEGORIES = %i[network timeout rate_limit upstream].freeze

    attr_reader :category, :http_status, :retry_after

    # retry_after is the server's hint in seconds (Retry-After header), when it sent one.
    def initialize(message, category:, http_status: nil, retry_after: nil)
      super(message)
      @category = category
      @http_status = http_status
      @retry_after = retry_after
    end

    # Auth, quota, invalid requests, schema problems, and unknown errors are never retried.
    def retryable?
      RETRYABLE_CATEGORIES.include?(category)
    end
  end

  # Raised before any request is made when credentials are missing.
  class NotConfigured < StandardError; end
end
