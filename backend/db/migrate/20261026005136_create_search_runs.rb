class CreateSearchRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :search_runs do |t|
      t.references :keyword, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :upstream_latency_ms
      t.integer :http_status
      t.string :error_category
      t.string :cache_source, null: false, default: "none"
      t.jsonb :request_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :search_runs, %i[keyword_id created_at]
    add_index :search_runs, :fingerprint
    add_index :search_runs, %i[status created_at]
  end
end
