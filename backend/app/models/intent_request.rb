class IntentRequest < ApplicationRecord
  OUTCOMES = %w[planned needs_clarification unsupported rejected failed].freeze
  TEXT_MAX_LENGTH = 500

  validates :original_text, presence: true, length: { maximum: TEXT_MAX_LENGTH }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :duration_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end
