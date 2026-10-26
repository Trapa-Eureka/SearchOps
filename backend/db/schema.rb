# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_26_005139) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "intent_requests", force: :cascade do |t|
    t.text "original_text", null: false
    t.string "classifier_version"
    t.jsonb "plan"
    t.string "outcome", null: false
    t.integer "duration_ms"
    t.string "fallback_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_intent_requests_on_created_at"
  end

  create_table "keywords", force: :cascade do |t|
    t.string "query", null: false
    t.string "engine", default: "google", null: false
    t.string "country", null: false
    t.string "language", null: false
    t.string "location"
    t.string "target_domain"
    t.boolean "active", default: true, null: false
    t.string "schedule", default: "manual", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "schedule"], name: "index_keywords_on_active_and_schedule"
    t.index ["query", "engine", "country", "language", "location", "target_domain"], name: "index_keywords_on_search_settings", unique: true, nulls_not_distinct: true
  end

  create_table "rank_snapshots", force: :cascade do |t|
    t.bigint "keyword_id", null: false
    t.bigint "search_run_id", null: false
    t.string "target_domain", null: false
    t.integer "rank"
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["keyword_id", "captured_at"], name: "index_rank_snapshots_on_keyword_id_and_captured_at"
    t.index ["keyword_id"], name: "index_rank_snapshots_on_keyword_id"
    t.index ["search_run_id"], name: "index_rank_snapshots_on_search_run_id", unique: true
    t.check_constraint "rank IS NULL OR rank >= 1", name: "rank_snapshots_rank_positive"
  end

  create_table "search_results", force: :cascade do |t|
    t.bigint "search_run_id", null: false
    t.integer "position", null: false
    t.string "title"
    t.text "url", null: false
    t.string "display_domain"
    t.text "snippet"
    t.jsonb "extra", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["search_run_id", "position"], name: "index_search_results_on_search_run_id_and_position", unique: true
    t.index ["search_run_id"], name: "index_search_results_on_search_run_id"
    t.check_constraint "\"position\" >= 1", name: "search_results_position_positive"
  end

  create_table "search_runs", force: :cascade do |t|
    t.bigint "keyword_id", null: false
    t.string "fingerprint", null: false
    t.string "status", default: "queued", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "upstream_latency_ms"
    t.integer "http_status"
    t.string "error_category"
    t.string "cache_source", default: "none", null: false
    t.jsonb "request_metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_search_runs_on_fingerprint"
    t.index ["keyword_id", "created_at"], name: "index_search_runs_on_keyword_id_and_created_at"
    t.index ["keyword_id"], name: "index_search_runs_on_keyword_id"
    t.index ["status", "created_at"], name: "index_search_runs_on_status_and_created_at"
  end

  add_foreign_key "rank_snapshots", "keywords"
  add_foreign_key "rank_snapshots", "search_runs"
  add_foreign_key "search_results", "search_runs"
  add_foreign_key "search_runs", "keywords"
end
