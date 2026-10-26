# Describes how a target domain's rank moved between two snapshots.
#
# A smaller rank is a better position, so delta = previous - current is positive
# when the domain moved up. The window is whatever one search returned, so
# "dropped" means "no longer in the retrieved window", not "ranks last".
#
# Snapshots are only compared when they come from equivalent searches (same
# settings fingerprint) for the same target domain.
class RankComparison
  Result = Data.define(:status, :delta, :previous_rank, :current_rank)

  STATUSES = %w[improved declined unchanged entered dropped not_found not_comparable baseline].freeze

  class << self
    # previous may be nil for the first snapshot (baseline).
    def between(previous:, current:)
      return build("baseline", nil, nil, current.rank) if previous.nil?
      return build("not_comparable", nil, previous.rank, current.rank) unless comparable?(previous, current)

      call(previous: previous.rank, current: current.rank)
    end

    def call(previous:, current:)
      if previous.nil? && current.nil?
        build("not_found", nil, previous, current)
      elsif previous.nil?
        build("entered", nil, previous, current)
      elsif current.nil?
        build("dropped", nil, previous, current)
      else
        delta = previous - current
        status = delta.positive? ? "improved" : (delta.negative? ? "declined" : "unchanged")
        build(status, delta, previous, current)
      end
    end

    def comparable?(first, second)
      first.target_domain == second.target_domain &&
        first.search_run.fingerprint == second.search_run.fingerprint
    end

    private

    def build(status, delta, previous, current)
      Result.new(status: status, delta: delta, previous_rank: previous, current_rank: current)
    end
  end
end
