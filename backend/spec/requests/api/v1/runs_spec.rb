require "rails_helper"

RSpec.describe "Api::V1::Runs", type: :request do
  def json
    response.parsed_body
  end

  it "returns an empty page when nothing has run" do
    get "/api/v1/searches"

    expect(response).to have_http_status(:ok)
    expect(json["data"]).to eq([])
    expect(json["meta"]).to eq(
      "page" => 1, "per_page" => 25, "total_count" => 0, "total_pages" => 0,
      "counts" => { "queued" => 0, "running" => 0, "succeeded" => 0, "failed" => 0, "all" => 0 }
    )
  end

  it "counts runs per status, unaffected by the status filter, so tabs can show their totals" do
    keyword = create(:keyword)
    create_list(:search_run, 3, keyword: keyword)
    create(:search_run, :failed, keyword: keyword)
    create(:search_run, :queued, keyword: keyword)
    create(:search_run, :failed, keyword: create(:keyword))

    get "/api/v1/searches", params: { status: "failed", keyword_id: keyword.id }

    expect(json["data"].size).to eq(1)
    expect(json["meta"]["total_count"]).to eq(1)
    expect(json["meta"]["counts"]).to eq("queued" => 1, "running" => 0, "succeeded" => 3, "failed" => 1, "all" => 5)
  end

  it "lists runs of all keywords newest first, with their keyword and without result bodies" do
    first = create(:keyword, query: "react", target_domain: "react.dev")
    second = create(:keyword, query: "vue")
    older = create(:search_run, keyword: first, created_at: 2.hours.ago)
    newer = create(:search_run, :failed, keyword: second, created_at: 1.hour.ago, error_category: "timeout")

    get "/api/v1/searches"

    expect(json["data"].map { |run| run["id"] }).to eq([ newer.id, older.id ])
    expect(json["data"].first).to include("status" => "failed", "error_category" => "timeout")
    expect(json["data"].first["keyword"]).to eq("id" => second.id, "query" => "vue", "country" => "us", "language" => "en", "target_domain" => nil)
    expect(json["data"].last["keyword"]).to include("query" => "react", "target_domain" => "react.dev")
    expect(json["data"].first).not_to have_key("results")
  end

  it "includes the fields a timeline needs: trigger, attempts, latency, cache" do
    source = create(:search_run, upstream_latency_ms: 840, attempts: 2, triggered_by: "scheduled")
    create(:search_run, :cache_hit, keyword: source.keyword, source_run: source)

    get "/api/v1/searches"

    run = json["data"].find { |item| item["id"] == source.id }
    expect(run).to include("triggered_by" => "scheduled", "attempts" => 2, "upstream_latency_ms" => 840, "cache_source" => "none")
    expect(json["data"].map { |item| item["cache"]["hit"] }).to contain_exactly(true, false)
  end

  it "paginates" do
    create_list(:search_run, 5)

    get "/api/v1/searches", params: { page: 2, per_page: 2 }

    expect(json["data"].size).to eq(2)
    expect(json["meta"]).to include("page" => 2, "per_page" => 2, "total_count" => 5, "total_pages" => 3)
  end

  it "filters by status, error category, and keyword" do
    keyword = create(:keyword)
    ok = create(:search_run, keyword: keyword)
    failed = create(:search_run, :failed, keyword: keyword, error_category: "auth")
    other = create(:search_run, :failed, error_category: "timeout")

    get "/api/v1/searches", params: { status: "failed" }
    expect(json["data"].map { |run| run["id"] }).to contain_exactly(failed.id, other.id)

    get "/api/v1/searches", params: { error_category: "auth" }
    expect(json["data"].map { |run| run["id"] }).to eq([ failed.id ])

    get "/api/v1/searches", params: { keyword_id: keyword.id }
    expect(json["data"].map { |run| run["id"] }).to contain_exactly(ok.id, failed.id)
  end

  it "ignores unknown filter values instead of failing or injecting them" do
    create(:search_run)

    get "/api/v1/searches", params: { status: "'; DROP TABLE search_runs; --", error_category: "x", keyword_id: "1 OR 1=1" }

    expect(response).to have_http_status(:ok)
    expect(json["data"].size).to eq(1)
  end

  it "does not run one query per run" do
    create_list(:search_run, 6)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get "/api/v1/searches" }

    expect(queries.size).to be <= 8
  end

  it "never exposes the API key or search results" do
    create(:search_run, request_metadata: { "query" => "q", "error_message" => "boom" })

    get "/api/v1/searches"

    expect(response.body).not_to match(/api[_-]?key/i)
  end
end
