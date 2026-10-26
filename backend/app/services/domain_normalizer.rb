# Canonicalizes a user-supplied domain or URL to a bare lowercase hostname.
#
# The result is only ever compared against result hostnames. It is never used
# as a fetch destination, so IPs, ports, userinfo and non-HTTP schemes are
# rejected rather than passed through (SSRF hygiene).
#
# Matching rule (used by rank tracking): a result host matches the target when
# it equals the target or is a subdomain of it ("blog.example.com" matches
# "example.com", "notexample.com" does not). A leading "www." is dropped from
# the target, so "www.example.com" and "example.com" mean the same thing.
class DomainNormalizer
  MAX_HOST_LENGTH = 253
  LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
  SCHEME = %r{\A([a-z][a-z0-9+.\-]*)://}
  ALLOWED_SCHEMES = %w[http https].freeze

  class << self
    # Returns the canonical hostname, or nil when the input is blank or invalid.
    def call(input)
      return nil unless input.is_a?(String)

      host = extract_host(input.strip.downcase)
      return nil if host.nil?

      host = host.delete_suffix(".").delete_prefix("www.")
      valid_host?(host) ? host : nil
    end

    # True when result_host equals target or is a subdomain of it.
    def match?(host:, target:)
      host = call(host)
      target = call(target)
      return false if host.nil? || target.nil?

      host == target || host.end_with?(".#{target}")
    end

    private

    def extract_host(value)
      return nil if value.empty?

      if (scheme = value[SCHEME, 1])
        return nil unless ALLOWED_SCHEMES.include?(scheme)

        value = value.sub(SCHEME, "")
      end

      authority = value.split(%r{[/?#]}, 2).first.to_s
      return nil if authority.include?("@")

      authority.sub(/:\d{1,5}\z/, "")
    end

    def valid_host?(host)
      return false if host.empty? || host.length > MAX_HOST_LENGTH

      labels = host.split(".", -1)
      return false if labels.length < 2
      return false unless labels.all? { |label| label.match?(LABEL) }

      # A numeric TLD means an IPv4-style address, which is not a domain.
      !labels.last.match?(/\A\d+\z/)
    end
  end
end
