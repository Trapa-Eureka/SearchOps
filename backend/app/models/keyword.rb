class Keyword < ApplicationRecord
  ENGINES = %w[google].freeze
  SCHEDULES = %w[manual daily weekly].freeze

  # Curated MVP subsets, not SerpApi's full lists. Verify against SerpApi's
  # supported gl/hl values before extending (Stage 3).
  COUNTRIES = %w[
    us gb ca au nz ie in sg ph my id th vn jp kr tw hk
    de fr es it nl se no dk fi pl br mx ar cl co za ae sa tr il
  ].freeze
  LANGUAGES = %w[en ko ja es fr de it pt nl sv no da fi pl tr id th vi tl hi ar ru he].freeze

  QUERY_MAX_LENGTH = 200
  LOCATION_MAX_LENGTH = 100
  DEFAULT_MAX_KEYWORDS = 50

  # Snapshots reference runs, so they are destroyed first (declaration order).
  has_many :rank_snapshots, dependent: :destroy
  has_many :search_runs, dependent: :destroy

  before_validation :normalize_fields

  validates :query, presence: true, length: { maximum: QUERY_MAX_LENGTH },
                    format: { without: /[[:cntrl:]]/, message: "contains control characters" }
  validates :engine, inclusion: { in: ENGINES }
  validates :country, inclusion: { in: COUNTRIES }
  validates :language, inclusion: { in: LANGUAGES }
  validates :schedule, inclusion: { in: SCHEDULES }
  validates :location, length: { maximum: LOCATION_MAX_LENGTH },
                       format: { without: /[[:cntrl:]]/, message: "contains control characters" },
                       allow_nil: true
  validates :active, inclusion: { in: [ true, false ] }
  validate :target_domain_is_valid_hostname
  validate :within_keyword_limit, on: :create
  # Declared last and skipped when anything else is invalid, so malformed values
  # (e.g. NUL bytes) never reach the uniqueness query.
  validates :query, uniqueness: {
    scope: %i[engine country language location target_domain],
    message: "already exists with the same search settings"
  }, unless: -> { errors.any? }

  scope :active, -> { where(active: true) }

  def self.max_keywords
    ENV.fetch("SEARCH_MAX_KEYWORDS", DEFAULT_MAX_KEYWORDS).to_i
  end

  private

  def normalize_fields
    self.query = query.to_s.squish
    self.engine = engine.to_s.strip.downcase.presence || engine
    self.country = country.to_s.strip.downcase.presence
    self.language = language.to_s.strip.downcase.presence
    self.schedule = schedule.to_s.strip.downcase.presence || schedule
    self.location = location.to_s.squish.presence
    # Keep the raw value when it is not a valid domain so validation can report it.
    self.target_domain = DomainNormalizer.call(target_domain) || target_domain.to_s.strip.presence
  end

  def target_domain_is_valid_hostname
    return if target_domain.nil?

    errors.add(:target_domain, "is not a valid domain") if DomainNormalizer.call(target_domain) != target_domain
  end

  def within_keyword_limit
    return if self.class.count < self.class.max_keywords

    errors.add(:base, "keyword limit reached (#{self.class.max_keywords})")
  end
end
