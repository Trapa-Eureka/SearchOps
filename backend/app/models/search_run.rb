class SearchRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed].freeze
  CACHE_SOURCES = %w[none app serpapi].freeze
  ERROR_CATEGORIES = %w[
    auth quota rate_limit network timeout invalid_request schema upstream unknown
  ].freeze

  belongs_to :keyword
  has_many :search_results, dependent: :delete_all
  has_one :rank_snapshot, dependent: :delete

  validates :fingerprint, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :cache_source, inclusion: { in: CACHE_SOURCES }
  validates :error_category, inclusion: { in: ERROR_CATEGORIES }, allow_nil: true
  validates :upstream_latency_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :http_status, numericality: { only_integer: true, in: 100..599 }, allow_nil: true
end
