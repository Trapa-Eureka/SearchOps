namespace :searchops do
  desc "Compare structured search (A), natural language through Laya (B), and Laya down (C) on the held-out sentences. " \
       "Uses a seeded FAKE provider (never SerpApi) and wipes the database it runs on, which must be named *_bench. " \
       "Env: REPEATS SEED PROVIDER_MEDIAN_MS PROVIDER_SIGMA PROVIDER_FAILURE_RATE HANG_SAMPLES OUT"
  task benchmark: :environment do
    abort "Run this against a scratch database: DATABASE_URL=postgresql:///searchops_bench RAILS_ENV=development" unless Rails.env.development?

    data = JSON.parse(Rails.root.join("spec/fixtures/intent/heldout_set.json").read)
    defaults = SearchOpsBenchmark::Runner::DEFAULT_CONFIG
    config = defaults.with(
      seed: Integer(ENV.fetch("SEED", defaults.seed)), repeats: Integer(ENV.fetch("REPEATS", defaults.repeats)),
      provider_median_ms: Float(ENV.fetch("PROVIDER_MEDIAN_MS", defaults.provider_median_ms)), provider_sigma: Float(ENV.fetch("PROVIDER_SIGMA", defaults.provider_sigma)),
      failure_rate: Float(ENV.fetch("PROVIDER_FAILURE_RATE", defaults.failure_rate)), hang_samples: Integer(ENV.fetch("HANG_SAMPLES", defaults.hang_samples))
    )

    result = SearchOpsBenchmark::Runner.new(items: data["items"], config: config).run
    report = SearchOpsBenchmark::Report.new(result)

    out = Pathname.new(ENV.fetch("OUT", Rails.root.join("tmp/benchmarks/#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.json").to_s))
    out.dirname.mkpath
    out.write(report.to_json)
    puts "\n#{report.markdown}\nraw records: #{out}"
  end
end

namespace :searchops do
  desc "Render the report of a saved benchmark run: FILE=path/to/run.json"
  task benchmark_report: :environment do
    file = ENV["FILE"] or abort "Usage: FILE=tmp/benchmarks/<run>.json bin/rails searchops:benchmark_report"
    puts SearchOpsBenchmark::Report.from_json(File.read(file)).markdown
  end
end
