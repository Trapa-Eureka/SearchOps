class RankSnapshot < ApplicationRecord
  belongs_to :keyword
  belongs_to :search_run

  # rank is nil when the domain was not found in the retrieved window. It is
  # never 0, and a smaller number is a better position.
  validates :rank, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validates :target_domain, presence: true
  validates :captured_at, presence: true
  validates :search_run_id, uniqueness: true
  validate :run_belongs_to_keyword

  def found?
    !rank.nil?
  end

  private

  def run_belongs_to_keyword
    return if search_run.nil? || keyword.nil?

    errors.add(:search_run, "must belong to the same keyword") if search_run.keyword_id != keyword_id
  end
end
