class IntentRequest < ApplicationRecord
  # planned: validated and waiting for the user's confirmation
  # needs_clarification: understood only in part (low confidence or missing fields)
  # unsupported: understood, but outside what this version can do
  # unavailable: the classifier is disabled or failed, so nothing was understood
  # executed: confirmed and carried out
  OUTCOMES = %w[planned needs_clarification unsupported unavailable executed].freeze
  TEXT_MAX_LENGTH = 500

  validates :original_text, presence: true, length: { maximum: TEXT_MAX_LENGTH }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :duration_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Deletes requests older than the retention window. The text is the only personal data kept.
  def self.purge_expired(now: Time.current, days: Intent::Config.retention_days)
    where(created_at: ...(now - days.days)).delete_all
  end
end
