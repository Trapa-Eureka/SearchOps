module Intent
  # Settings for the optional natural-language path. Everything here has a safe default,
  # and nothing in the core search flow reads it.
  module Config
    DEFAULT_URL = "http://127.0.0.1:8765".freeze
    DEFAULT_MODEL = "multilingual".freeze
    DEFAULT_TIMEOUT_SECONDS = 4.0
    # Measured on the dev split of spec/fixtures/intent/eval_set.json: answers with a top
    # probability of at least 0.7 were about 87% correct, against 73% overall.
    DEFAULT_MIN_CONFIDENCE = 0.7
    DEFAULT_RETENTION_DAYS = 30
    # What the running laya-serve is, for the audit trail (it is not reported by the server).
    DEFAULT_VERSION_LABEL = "0.4.15@7b928d8".freeze

    class << self
      TRUE_VALUES = %w[true 1 yes on].freeze

      # Only an explicit true value enables Laya. Anything else, including a typo, leaves it off.
      def enabled?
        TRUE_VALUES.include?(ENV.fetch("LAYA_ENABLED", "false").to_s.strip.downcase)
      end

      def url
        ENV.fetch("LAYA_URL", DEFAULT_URL).to_s.strip
      end

      def api_key
        ENV["LAYA_API_KEY"].to_s.strip.presence
      end

      def model
        ENV.fetch("LAYA_MODEL", DEFAULT_MODEL).to_s.strip
      end

      def timeout_seconds
        value = Float(ENV.fetch("LAYA_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_s, exception: false)
        value&.positive? ? value.clamp(0.1, 30.0) : DEFAULT_TIMEOUT_SECONDS
      end

      # An unreadable value falls back to the default, and values outside 0..1 are clamped.
      def min_confidence
        value = Float(ENV.fetch("LAYA_MIN_CONFIDENCE", DEFAULT_MIN_CONFIDENCE).to_s, exception: false)
        value.nil? ? DEFAULT_MIN_CONFIDENCE : value.clamp(0.0, 1.0)
      end

      def retention_days
        value = Integer(ENV.fetch("INTENT_RETENTION_DAYS", DEFAULT_RETENTION_DAYS).to_s, 10, exception: false)
        value&.positive? ? value : DEFAULT_RETENTION_DAYS
      end

      def version_label
        ENV.fetch("LAYA_VERSION_LABEL", DEFAULT_VERSION_LABEL).to_s.strip
      end
    end
  end
end
