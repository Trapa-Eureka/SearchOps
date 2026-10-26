class AddExecutionTrackingToSearchRuns < ActiveRecord::Migration[8.1]
  def change
    change_table :search_runs, bulk: true do |t|
      t.string :triggered_by, null: false, default: "manual"
      # Attempts started by a worker (first try plus retries).
      t.integer :attempts, null: false, default: 0
      # Requests actually sent to SerpApi. Drives the daily budget; cache hits stay at 0.
      t.integer :upstream_calls, null: false, default: 0
      # For a local cache hit: the run whose results were served.
      t.references :source_run, foreign_key: { to_table: :search_runs, on_delete: :nullify }, index: true
    end

    # At most one queued or running run per keyword and search settings, so concurrent
    # requests (or a double-firing scheduler) cannot start duplicate upstream calls.
    add_index :search_runs, %i[keyword_id fingerprint],
              unique: true,
              where: "status IN ('queued', 'running')",
              name: "index_search_runs_one_active_per_keyword_and_fingerprint"
    # Cache lookup: latest finished run for a keyword and settings.
    add_index :search_runs, %i[keyword_id fingerprint finished_at],
              name: "index_search_runs_for_cache_lookup"
    add_index :search_runs, :created_at
    add_check_constraint :search_runs, "attempts >= 0 AND upstream_calls >= 0", name: "search_runs_counters_non_negative"
  end
end
