# Entry point for "search this keyword now", for the API and for the scheduler.
#
# Decides, in order, whether the request can be answered without a new upstream call:
#   1. cache hit      a recent successful run for the same settings is reused (unless refresh)
#   2. deduplicated   a queued/running run for the same settings already exists
#   3. enqueued       otherwise a queued run is created and ExecuteSearchJob is scheduled
# The daily budget is checked only before case 3, and nothing is created when it is spent.
class SearchEnqueuer
  Result = Data.define(:run, :outcome)

  def initialize(budget: SearchBudget, cache: SearchCache)
    @budget = budget
    @cache = cache
  end

  # Raises SearchBudget::Exceeded. refresh: true skips the cache (still deduplicated and budgeted).
  def call(keyword, refresh: false, triggered_by: "manual")
    request = SearchProvider::Request.from_keyword(keyword)
    fingerprint = SearchFingerprint.call(request)

    unless refresh
      source = @cache.lookup(keyword: keyword, fingerprint: fingerprint)
      return cache_hit(keyword, request, fingerprint, source, triggered_by) if source
    end

    active = active_run(keyword, fingerprint)
    return deduplicated(active) if active

    @budget.check!
    enqueue(keyword, request, fingerprint, triggered_by)
  end

  private

  def enqueue(keyword, request, fingerprint, triggered_by)
    run = keyword.search_runs.create!(
      fingerprint: fingerprint, status: "queued", triggered_by: triggered_by, request_metadata: provenance(request)
    )
    ExecuteSearchJob.perform_later(run.id)
    Rails.logger.info("search_enqueued run_id=#{run.id} keyword_id=#{keyword.id} triggered_by=#{triggered_by}")
    Result.new(run: run, outcome: :enqueued)
  rescue ActiveRecord::RecordNotUnique
    # Another request created the active run between our check and our insert.
    existing = active_run(keyword, fingerprint)
    raise if existing.nil?

    deduplicated(existing)
  end

  def cache_hit(keyword, request, fingerprint, source, triggered_by)
    now = Time.current
    age = (now - source.finished_at).round
    run = keyword.search_runs.create!(
      fingerprint: fingerprint, status: "succeeded", cache_source: "app", source_run: source,
      triggered_by: triggered_by, started_at: now, finished_at: now,
      request_metadata: provenance(request).merge(
        "search_id" => source.request_metadata["search_id"],
        "result_count" => source.request_metadata["result_count"],
        "empty_results" => source.request_metadata["empty_results"],
        "cache_age_seconds" => age
      )
    )
    Rails.logger.info("search_cache_hit run_id=#{run.id} keyword_id=#{keyword.id} source_run_id=#{source.id} age_seconds=#{age}")
    Result.new(run: run, outcome: :cache_hit)
  end

  def deduplicated(run)
    Rails.logger.info("search_deduplicated run_id=#{run.id} keyword_id=#{run.keyword_id}")
    Result.new(run: run, outcome: :deduplicated)
  end

  def active_run(keyword, fingerprint)
    keyword.search_runs.active.find_by(fingerprint: fingerprint)
  end

  # Enough to explain a ranking difference later: what was asked, of which provider.
  def provenance(request)
    {
      "provider" => "serpapi", "engine" => request.engine, "query" => request.query,
      "country" => request.country, "language" => request.language, "location" => request.location
    }
  end
end
