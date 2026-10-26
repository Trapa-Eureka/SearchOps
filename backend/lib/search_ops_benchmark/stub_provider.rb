require "digest"

module SearchOpsBenchmark
  # A stand-in for SerpApi with a deterministic, seeded behaviour, so every mode of the
  # comparison faces exactly the same "network": the latency and the failure of the n-th
  # attempt for a given search depend only on (seed, search, n), never on the order in which
  # the modes or the searches ran.
  #
  # It makes NO claim about SerpApi: the median latency and the failure rate are inputs. It
  # does sleep for the sampled latency, so measured request times include it.
  class StubProvider
    MAX_LATENCY_MS = 15_000
    RESULT_COUNT = 5

    Call = Data.define(:key, :attempt, :latency_ms, :failed)

    attr_reader :calls

    # targets: { "query|country|language" => "target.domain" }. The target is placed at a
    # deterministic position 1..5, or left out (not found) one time in six.
    def initialize(seed:, median_ms:, sigma:, failure_rate:, targets: {}, sleeper: Kernel.method(:sleep))
      @seed = seed
      @median_ms = median_ms
      @sigma = sigma
      @failure_rate = failure_rate
      @targets = targets
      @sleeper = sleeper
      reset!
    end

    # Forget what happened, so the next mode starts with the same attempt numbering.
    def reset!
      @attempts = Hash.new(0)
      @calls = []
    end

    def search(request)
      key = self.class.key_for(request)
      attempt = (@attempts[key] += 1)
      latency = latency_ms(key, attempt)
      @sleeper.call(latency / 1000.0)
      failed = uniform(key, attempt, "failure") < @failure_rate
      @calls << Call.new(key: key, attempt: attempt, latency_ms: latency, failed: failed)
      raise SearchProvider::Error.new("injected transient failure", category: :upstream, http_status: 503) if failed

      SearchProvider::Response.new(results: results_for(key), empty: false, search_id: "bench-#{Digest::SHA256.hexdigest(key)[0, 8]}", skipped_count: 0)
    end

    def self.key_for(request)
      [ request.query, request.country, request.language ].join("|")
    end

    def latency_ms(key, attempt)
      u1 = [ uniform(key, attempt, "latency-a"), 1e-12 ].max
      u2 = uniform(key, attempt, "latency-b")
      z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2) # standard normal (Box-Muller)
      [ (@median_ms * Math.exp(@sigma * z)).round, MAX_LATENCY_MS ].min
    end

    # Where the target sits for this search: 1..RESULT_COUNT, or nil for "not in the window".
    def target_position(key)
      position = 1 + (Integer(Digest::SHA256.hexdigest("#{@seed}|#{key}|position")[0, 8], 16) % (RESULT_COUNT + 1))
      position > RESULT_COUNT ? nil : position
    end

    private

    def uniform(key, attempt, salt)
      Integer(Digest::SHA256.hexdigest("#{@seed}|#{key}|#{attempt}|#{salt}")[0, 13], 16) / (16.0**13)
    end

    def results_for(key)
      target = @targets[key]
      at = target && target_position(key)
      (1..RESULT_COUNT).map do |position|
        host = position == at ? target : "site#{position}.test"
        SearchProvider::Result.new(position: position, title: "Result #{position}", url: "https://#{host}/page", display_domain: host,
                                   snippet: "benchmark snippet #{position}", extra: {})
      end
    end
  end
end
