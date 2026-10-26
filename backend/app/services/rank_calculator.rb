# Position of a target domain within one retrieved result window.
#
# Returns the smallest position among results whose host equals the target or is
# a subdomain of it (see DomainNormalizer.match?). Returns nil when the target is
# blank or not found: nil means "not found in the retrieved window", never 0.
# A smaller number is a better position.
class RankCalculator
  def self.call(results:, target_domain:)
    return nil if target_domain.blank?

    results
      .select { |result| DomainNormalizer.match?(host: result.url, target: target_domain) }
      .map(&:position)
      .min
  end
end
