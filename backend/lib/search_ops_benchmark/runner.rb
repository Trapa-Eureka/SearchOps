require "socket"
require "digest"

module SearchOpsBenchmark
  # Runs the comparison of the three ways of getting a search done:
  #
  #   A  structured: the person fills in the keyword form (no Laya anywhere)
  #   B  natural language: sentence -> Laya -> validated plan -> confirmation -> the same search path
  #   C  Laya unavailable: the sentence gets a fallback, the person uses the keyword form
  #
  # Every mode starts from an empty database and the same seeded fake provider, goes through the real
  # Rails stack in-process, and is run twice over the same tasks: a cold pass (nothing cached) and a warm
  # pass (the cache is warm). Nothing reaches SerpApi; the provider's latency and failures are inputs.
  class Runner
    Config = Data.define(:seed, :repeats, :provider_median_ms, :provider_sigma, :failure_rate, :hang_samples, :laya_url)

    DEFAULT_CONFIG = Config.new(seed: 20_261_026, repeats: 3, provider_median_ms: 900, provider_sigma: 0.35, failure_rate: 0.3, hang_samples: 3, laya_url: nil)
    REFUSED_URL = "http://127.0.0.1:1".freeze
    FIELDS = Policies::FIELDS

    def initialize(items:, config: DEFAULT_CONFIG, client: nil, sleeper: Kernel.method(:sleep), out: $stdout, allowed_databases: %w[_bench], modes: nil)
      @items = items
      @config = config
      @client = client
      @sleeper = sleeper
      @out = out
      @allowed_databases = allowed_databases
      @only_modes = modes
      @tasks = items.select { |item| item["task"] }
    end

    def run
      database = DatabaseGuard.check!(allowed_suffixes: @allowed_databases)
      with_environment do
        @client ||= ApiClient.new
        @adapter = ImmediateQueueAdapter.new
        ActiveJob::Base.queue_adapter = @adapter
        repetitions = (1..@config.repeats).map { |number| repetition(number) }
        { meta: meta(database), repetitions: repetitions }
      end
    end

    private

    def repetition(number)
      seed = @config.seed + number
      @provider = StubProvider.new(seed: seed, median_ms: @config.provider_median_ms, sigma: @config.provider_sigma,
                                   failure_rate: @config.failure_rate, targets: targets, sleeper: @sleeper)
      ExecuteSearchJob.provider_factory = -> { @provider }
      @out.puts "repetition #{number}/#{@config.repeats} (seed #{seed})"

      modes = []
      modes << mode("A", nil) { structured_mode } if wanted?("A")
      modes << mode("B", "diligent") { natural_language_mode(Policies::Diligent.new, warm_pass: true) } if wanted?("B")
      modes << mode("B", "careless") { natural_language_mode(Policies::Careless.new, warm_pass: false) } if wanted?("B-careless")
      modes << mode("C", "laya refusing connections") { laya_down_mode } if wanted?("C")
      modes << mode("C", "laya hanging") { laya_hanging_mode } if wanted?("C-hang") && number == 1
      { seed: seed, modes: modes }
    end

    def wanted?(name)
      @only_modes.nil? || @only_modes.include?(name)
    end

    def targets
      @tasks.to_h { |item| [ item["task"].values_at("query", "country", "language").join("|"), item["task"]["target_domain"] ] }
    end

    def mode(name, policy)
      DatabaseGuard.wipe!
      @provider.reset!
      @adapter.delays.clear
      @out.puts "  mode #{name}#{" (#{policy})" if policy}"
      { name: name, policy: policy, records: yield }
    end

    # ---- modes

    def structured_mode
      cold = @tasks.map { |item| record("cold", item) { |rec| structured(rec, item) } }
      warm = @tasks.map { |item| record("warm", item) { |rec| structured(rec, item) } }
      cold + warm
    end

    def natural_language_mode(policy, warm_pass:)
      warm_up_laya
      cold = @items.map { |item| record("cold", item) { |rec| natural_language(rec, item, policy) } }
      warm = warm_pass ? @tasks.map { |item| record("warm", item) { |rec| natural_language(rec, item, policy) } } : []
      cold + warm
    end

    def laya_down_mode
      with_laya_url(REFUSED_URL) do
        policy = Policies::Diligent.new
        cold = @items.map { |item| record("cold", item) { |rec| natural_language(rec, item, policy) } }
        warm = @tasks.map { |item| record("warm", item) { |rec| natural_language(rec, item, policy) } }
        cold + warm
      end
    end

    # Laya accepts the connection and never answers: the person waits for the client's timeout.
    def laya_hanging_mode
      with_hanging_server do |url|
        with_laya_url(url) do
          @items.first(@config.hang_samples).map { |item| record("cold", item) { |rec| natural_language(rec, item, Policies::Careless.new, plan_only: true) } }
        end
      end
    end

    # ---- flows

    def record(pass, item)
      rec = { pass: pass, item_id: item["id"], intent: item["intent"], lang: item["lang"], has_task: item["task"].present?, task: item["task"], text_length: item["text"].to_s.length,
              steps: {}, provider_calls: 0, provider_ms: 0, attempt_latencies: [], failed_attempts: 0, backoff_ms: 0.0, edits: 0,
              completed: false, correct: false, cache_hit: false, fallback: false, error_code: nil }
      yield rec
      rec[:ms] = rec[:steps].values.sum
      rec[:unnecessary_calls] = !rec[:has_task] || rec[:keyword_matches_task] == false ? rec[:provider_calls] : 0
      rec
    end

    # Runs the block, charging the provider time and the retry waiting it caused to the record.
    def step(rec, name)
      calls_before = @provider.calls.size
      delays_before = @adapter.delays.size
      result = yield
      calls = @provider.calls[calls_before..]
      rec[:steps][name] = result.ms
      rec[:provider_calls] += calls.size
      rec[:provider_ms] += calls.sum(&:latency_ms)
      rec[:attempt_latencies].concat(calls.map(&:latency_ms))
      rec[:failed_attempts] += calls.count(&:failed)
      rec[:backoff_ms] += @adapter.delays[delays_before..].sum * 1000
      result
    end

    def structured(rec, item)
      task = item["task"]
      keyword = find_keyword(task)
      if keyword.nil?
        created = step(rec, "create_keyword") { @client.create_keyword(task) }
        keyword = Keyword.find_by(id: created.body.dig("data", "id"))
        return rec[:error_code] = created.body.dig("error", "code") || "keyword_not_created" if keyword.nil?
      end

      searched = step(rec, "search") { @client.search(keyword.id) }
      return rec[:error_code] = searched.body.dig("error", "code") if searched.status >= 400

      finish_search(rec, item, keyword, searched.body.dig("meta", "outcome"), SearchRun.find_by(id: searched.body.dig("data", "id")))
    end

    def natural_language(rec, item, policy, plan_only: false)
      planned = step(rec, "plan") { @client.plan(item["text"]) }
      body = planned.body["data"]
      return rec[:error_code] = planned.body.dig("error", "code") if body.nil?

      rec.merge!(plan_status: body["status"], plan_reason: body["reason"], predicted_intent: body.dig("classifier", "intent"),
                 laya_ms: body.dig("classifier", "latency_ms"), plan_errors: body["errors"].present?, plan: body["plan"]&.slice("intent", *FIELDS))
      return if plan_only

      action, edits = policy.decide(item, body)
      rec[:decision] = action.to_s
      case action
      when :confirm then confirm(rec, item, body, edits)
      when :structured
        rec[:fallback] = true
        structured(rec, item)
      end
    end

    def confirm(rec, item, body, edits)
      rec[:edits] = item["task"] ? Policies.edits_needed(body["plan"], item["task"]) : 0 if edits
      confirmed = step(rec, "confirm") { @client.confirm(body["id"], edits) }
      return rec[:error_code] = confirmed.body.dig("error", "code") if confirmed.status >= 400

      execution = confirmed.body.dig("data", "execution") || {}
      rec[:executed_kind] = execution["kind"]
      return unless execution["kind"] == "search"

      finish_search(rec, item, Keyword.find_by(id: execution["keyword_id"]), execution["search_outcome"], SearchRun.find_by(id: execution["run_id"]))
    end

    def finish_search(rec, item, keyword, outcome, run)
      task = item["task"]
      rec[:search_outcome] = outcome
      rec[:cache_hit] = outcome == "cache_hit"
      rec[:run_status] = run&.status
      rec[:attempts] = run&.attempts
      rec[:keyword_matches_task] = task.present? && !keyword.nil? && FIELDS.all? { |field| keyword.public_send(field) == task[field] }
      rec[:completed] = run&.status == "succeeded"
      rec[:correct] = rec[:completed] && rec[:keyword_matches_task]
    end

    def find_keyword(task)
      Keyword.find_by(task.slice(*FIELDS).merge("engine" => "google", "location" => nil))
    end

    # ---- environment

    def with_environment
      saved = %w[SERPAPI_API_KEY SEARCH_MAX_REQUESTS_PER_DAY SEARCH_CACHE_TTL_SECONDS LAYA_ENABLED LAYA_URL].to_h { |name| [ name, ENV.fetch(name, nil) ] }
      previous = { adapter: ActiveJob::Base.queue_adapter, factory: ExecuteSearchJob.provider_factory, level: Rails.logger.level }
      # The key is never used (the provider is replaced) but the API refuses to search without one.
      ENV["SERPAPI_API_KEY"] = "benchmark-not-a-real-key"
      ENV["SEARCH_MAX_REQUESTS_PER_DAY"] = "1000000"
      ENV["SEARCH_CACHE_TTL_SECONDS"] = "3600"
      ENV["LAYA_ENABLED"] = "true"
      ENV["LAYA_URL"] = @config.laya_url if @config.laya_url
      Rails.logger.level = Logger::WARN
      yield
    ensure
      saved&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
      ActiveJob::Base.queue_adapter = previous[:adapter] if previous
      ExecuteSearchJob.provider_factory = previous[:factory] if previous
      Rails.logger.level = previous[:level] if previous
    end

    def with_laya_url(url)
      original = ENV.fetch("LAYA_URL", nil)
      ENV["LAYA_URL"] = url
      yield
    ensure
      original.nil? ? ENV.delete("LAYA_URL") : ENV["LAYA_URL"] = original
    end

    def with_hanging_server
      server = TCPServer.new("127.0.0.1", 0)
      acceptor = Thread.new do
        loop do
          connection = server.accept
          Thread.new(connection) { |socket| sleep 60; socket.close }
        end
      rescue IOError, Errno::EBADF
        nil
      end
      yield "http://127.0.0.1:#{server.addr[1]}"
    ensure
      acceptor&.kill
      server&.close
    end

    # The first request after a quiet period can be slow (the model is paged in). Warm it up
    # outside the measurement and remember how long it took, because that is worth knowing.
    def warm_up_laya
      return if @warmup_ms

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Intent::LayaClassifier.new(url: Intent::Config.url, model: Intent::Config.model, timeout: 30).classify("warm-up")
      @warmup_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      @out.puts "    Laya warm-up request: #{@warmup_ms} ms (not measured)"
    end

    def meta(database)
      fixture = Rails.root.join("spec/fixtures/intent/heldout_set.json")
      {
        measured_at: Time.current.utc.iso8601, database: database, ruby: RUBY_VERSION, rails: Rails.version,
        config: @config.to_h, sentences: @items.size, tasks: @tasks.size, laya_warmup_ms: @warmup_ms,
        laya_model: Intent::Config.model, laya_version: Intent::Config.version_label,
        heldout_sha256: fixture.exist? ? Digest::SHA256.file(fixture).hexdigest[0, 16] : nil
      }
    end
  end
end
