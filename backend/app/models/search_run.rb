class SearchRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed].freeze
  ACTIVE_STATUSES = %w[queued running].freeze
  CACHE_SOURCES = %w[none app serpapi].freeze
  TRIGGERS = %w[manual scheduled].freeze
  # budget: the daily budget was spent before the call. abandoned: a worker never
  # finished the run (crash or lost job) and the reaper closed it.
  ERROR_CATEGORIES = %w[
    auth quota rate_limit network timeout invalid_request schema upstream unknown budget abandoned
  ].freeze

  belongs_to :keyword
  # Set when the run was answered from the local cache: the run whose results were served.
  belongs_to :source_run, class_name: "SearchRun", optional: true
  has_many :search_results, dependent: :delete_all
  has_one :rank_snapshot, dependent: :delete

  validates :fingerprint, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :cache_source, inclusion: { in: CACHE_SOURCES }
  validates :triggered_by, inclusion: { in: TRIGGERS }
  validates :error_category, inclusion: { in: ERROR_CATEGORIES }, allow_nil: true
  validates :upstream_latency_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :http_status, numericality: { only_integer: true, in: 100..599 }, allow_nil: true
  validates :attempts, :upstream_calls, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :source_run_matches_cache_source

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  # Runs that went (or were meant to go) to the provider, as opposed to local cache hits.
  scope :upstream, -> { where.not(cache_source: "app") }
  scope :finished, -> { where(status: %w[succeeded failed]) }

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def cache_hit?
    cache_source == "app"
  end

  # Where this run's results live: itself, or the cached run it was served from.
  def results_run
    source_run || self
  end

  private

  def source_run_matches_cache_source
    return if cache_hit? == source_run_id.present?

    errors.add(:source_run, cache_hit? ? "is required for a cache hit" : "is only allowed for a cache hit")
  end
end
