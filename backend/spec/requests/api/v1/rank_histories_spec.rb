require "rails_helper"

RSpec.describe "Api::V1::RankHistories", type: :request do
  # A method, not a memoized let: examples that send several requests must read the latest response.
  def json
    response.parsed_body
  end
  let(:keyword) { create(:keyword, target_domain: "example.com") }

  def snapshot(rank:, at:, fingerprint: "fp-1", target: "example.com")
    run = create(:search_run, keyword: keyword, fingerprint: fingerprint, created_at: at)
    create(:rank_snapshot, keyword: keyword, search_run: run, rank: rank, target_domain: target, captured_at: at)
  end

  it "returns an empty history with explicit semantics when nothing was captured" do
    get "/api/v1/keywords/#{keyword.id}/rank_history"

    expect(response).to have_http_status(:ok)
    expect(json["data"]).to eq([])
    expect(json["meta"]).to include(
      "target_domain" => "example.com", "ordering" => "newest_first", "rank_semantics" => "lower_is_better",
      "null_rank_meaning" => "not_found_in_retrieved_window", "total_count" => 0
    )
  end

  it "lists snapshots newest first and describes each change against the previous one" do
    snapshot(rank: 8, at: 4.days.ago)
    snapshot(rank: 5, at: 3.days.ago)
    snapshot(rank: 5, at: 2.days.ago)
    snapshot(rank: nil, at: 1.day.ago)
    snapshot(rank: 3, at: 1.hour.ago)

    get "/api/v1/keywords/#{keyword.id}/rank_history"

    summary = json["data"].map { |s| [ s["rank"], s["comparison"]["status"], s["comparison"]["delta"] ] }
    expect(summary).to eq([
      [ 3, "entered", nil ],
      [ nil, "dropped", nil ],
      [ 5, "unchanged", 0 ],
      [ 5, "improved", 3 ],
      [ 8, "baseline", nil ]
    ])
    expect(json["data"].first["comparison"]["previous_rank"]).to be_nil
    expect(json["data"].map { |s| s["found"] }).to eq([ true, false, true, true, true ])
  end

  it "labels a null rank as not found, not zero" do
    snapshot(rank: nil, at: 1.hour.ago)

    get "/api/v1/keywords/#{keyword.id}/rank_history"

    entry = json["data"].first
    expect(entry["rank"]).to be_nil
    expect(entry["found"]).to be(false)
  end

  it "marks snapshots as not comparable when the search settings differ" do
    snapshot(rank: 4, at: 2.days.ago, fingerprint: "fp-old")
    snapshot(rank: 2, at: 1.day.ago, fingerprint: "fp-new")

    get "/api/v1/keywords/#{keyword.id}/rank_history"

    newest = json["data"].first
    expect(newest["comparison"]).to eq("status" => "not_comparable", "delta" => nil, "previous_rank" => 4)
  end

  it "marks snapshots as not comparable when the target domain differs" do
    snapshot(rank: 4, at: 2.days.ago, target: "old-target.com")
    snapshot(rank: 2, at: 1.day.ago)

    get "/api/v1/keywords/#{keyword.id}/rank_history"

    expect(json["data"].first["comparison"]["status"]).to eq("not_comparable")
  end

  it "compares the oldest entry on a page with the first entry of the next page" do
    snapshot(rank: 9, at: 4.days.ago)
    snapshot(rank: 6, at: 3.days.ago)
    snapshot(rank: 4, at: 2.days.ago)
    snapshot(rank: 1, at: 1.day.ago)

    get "/api/v1/keywords/#{keyword.id}/rank_history", params: { per_page: 2 }
    first_page = json["data"].map { |s| [ s["rank"], s["comparison"]["status"], s["comparison"]["delta"] ] }

    expect(first_page).to eq([ [ 1, "improved", 3 ], [ 4, "improved", 2 ] ])
    expect(json["meta"]).to include("page" => 1, "per_page" => 2, "total_count" => 4, "total_pages" => 2)

    get "/api/v1/keywords/#{keyword.id}/rank_history", params: { per_page: 2, page: 2 }
    # `json` is memoized from the first request, so read the new response directly.
    second_page = response.parsed_body["data"].map { |s| [ s["rank"], s["comparison"]["status"] ] }

    expect(second_page).to eq([ [ 6, "improved" ], [ 9, "baseline" ] ])
  end

  it "returns an empty page beyond the last page" do
    snapshot(rank: 1, at: 1.day.ago)

    get "/api/v1/keywords/#{keyword.id}/rank_history", params: { page: 5 }

    expect(json["data"]).to eq([])
    expect(json["meta"]["total_count"]).to eq(1)
  end

  it "only includes snapshots of the requested keyword" do
    snapshot(rank: 2, at: 1.day.ago)
    create(:rank_snapshot) # another keyword

    get "/api/v1/keywords/#{keyword.id}/rank_history"

    expect(json["data"].size).to eq(1)
  end

  it "returns 404 for an unknown keyword" do
    get "/api/v1/keywords/0/rank_history"

    expect(response).to have_http_status(:not_found)
    expect(json["error"]["code"]).to eq("not_found")
  end

  describe "full flow with the real search endpoint",
           env: { "SERPAPI_API_KEY" => "flow-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "50", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
    include ActiveJob::TestHelper

    it "tracks a rank change between two searches" do
      stub_serpapi(fixture: "success") # example.com at position 2
      perform_enqueued_jobs { post "/api/v1/keywords/#{keyword.id}/searches" }
      expect(response).to have_http_status(:accepted)

      moved_up = JSON.parse(serpapi_fixture("success"))
      moved_up["organic_results"] = moved_up["organic_results"].rotate(1).each_with_index.map { |r, i| r.merge("position" => i + 1) }
      # rotate(1) moves the example.com result (position 2) to position 1
      stub_serpapi(body: moved_up.to_json)
      perform_enqueued_jobs { post "/api/v1/keywords/#{keyword.id}/searches", params: { refresh: "true" } }
      expect(response).to have_http_status(:accepted)

      get "/api/v1/keywords/#{keyword.id}/rank_history"

      expect(json["data"].map { |s| [ s["rank"], s["comparison"]["status"], s["comparison"]["delta"] ] })
        .to eq([ [ 1, "improved", 1 ], [ 2, "baseline", nil ] ])
      expect(json["meta"]["freshness"]).to include("state" => "fresh")
    end

    it "does not add a snapshot when the second search is served from the cache" do
      stub_serpapi(fixture: "success")
      perform_enqueued_jobs { post "/api/v1/keywords/#{keyword.id}/searches" }
      post "/api/v1/keywords/#{keyword.id}/searches"
      expect(response).to have_http_status(:ok)

      get "/api/v1/keywords/#{keyword.id}/rank_history"

      expect(json["data"].size).to eq(1)
    end
  end
end
