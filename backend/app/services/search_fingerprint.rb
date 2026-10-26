require "digest"
require "json"

# Stable digest of the settings that determine what a search returns:
# engine, query, country, language, and location. Two runs with the same
# fingerprint are comparable; a different one is not.
#
# The query and location are case-folded because the search is not
# case-sensitive in practice, so "React" and "react" share a fingerprint.
# Target domain is deliberately excluded (it does not change the SERP).
# The Stage 4 idempotency window is a separate concern layered on top of this.
class SearchFingerprint
  def self.call(request)
    parts = [
      request.engine.to_s,
      request.query.to_s.squish.downcase,
      request.country.to_s.downcase,
      request.language.to_s.downcase,
      request.location.to_s.squish.downcase
    ]
    Digest::SHA256.hexdigest(JSON.generate(parts))
  end
end
