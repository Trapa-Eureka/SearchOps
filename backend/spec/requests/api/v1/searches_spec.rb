require "rails_helper"

RSpec.describe "Api::V1::Searches", type: :request do
  let(:json) { response.parsed_body }
  let(:api_key) { "request-spec-key-123456" }
  let(:keyword) do
    create(:keyword, query: "react developer", country: "ph", language: "en", location: "Manila", target_domain: "example.com")
  end

  # Real adapter, real orchestrator, real database. Only the HTTP call to SerpApi is stubbed.
  describe "POST /api/v1/keywords/:keyword_id/searches",
           env: { "SERPAPI_API_KEY" => "request-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "50" } do
    it "runs a search and returns the normalized results with the target rank" do
      stub = stub_serpapi(fixture: "success")

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:created)
      expect(stub).to have_been_requested.once

      data = json["data"]
      expect(response.headers["Location"]).to eq("/api/v1/keywords/#{keyword.id}/searches/#{data['id']}")
      expect(data).to include("status" => "succeeded", "http_status" => 200, "error_category" => nil, "result_count" => 5)
      expect(data["upstream_latency_ms"]).to be >= 0
      expect(data["rank"]).to eq("target_domain" => "example.com", "rank" => 2, "found" => true)
      expect(data["request"]).to include("engine" => "google", "query" => "react developer", "country" => "ph",
                                         "language" => "en", "location" => "Manila", "search_id" => "fixture-success-1")
      expect(data["results"].map { |r| r["position"] }).to eq([ 1, 2, 3, 4, 5 ])
      expect(data["results"][1]).to eq(
        "position" => 2, "title" => "React developer jobs", "url" => "https://www.example.com/jobs/react",
        "display_domain" => "example.com", "snippet" => "Find remote React roles."
      )
    end

    it "sends the keyword's settings to SerpApi" do
      stub = stub_request(:get, "https://serpapi.com/search")
             .with(query: hash_including("q" => "react developer", "gl" => "ph", "hl" => "en", "location" => "Manila",
                                         "engine" => "google"))
             .to_return(status: 200, body: serpapi_fixture("success"))

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(stub).to have_been_requested.once
    end

    it "never exposes the API key in the response" do
      stub_serpapi(fixture: "success")

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response.body).not_to include(api_key)
    end

    it "treats an empty SERP as a successful run with a null rank" do
      stub_serpapi(fixture: "empty")

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("status" => "succeeded", "result_count" => 0, "empty_results" => true, "results" => [])
      expect(json["data"]["rank"]).to eq("target_domain" => "example.com", "rank" => nil, "found" => false)
    end

    it "reports a null rank when the target domain is not in the results" do
      keyword.update!(target_domain: "absent.org")
      stub_serpapi(fixture: "success")

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(json["data"]["rank"]).to include("rank" => nil, "found" => false)
    end

    it "skips the rank snapshot when the keyword has no target domain" do
      keyword.update!(target_domain: nil)
      stub_serpapi(fixture: "success")

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(json["data"]["rank"]).to be_nil
      expect(RankSnapshot.count).to eq(0)
    end

    {
      [ 401, "invalid_api_key" ] => [ :bad_gateway, "auth" ],
      [ 400, "missing_query" ] => [ :bad_gateway, "invalid_request" ],
      [ 429, "out_of_searches" ] => [ :too_many_requests, "quota" ],
      [ 503, "server_error" ] => [ :bad_gateway, "upstream" ]
    }.each do |(upstream_status, fixture), (http_status, category)|
      it "returns #{http_status} and records a failed run for upstream #{upstream_status} (#{category})" do
        stub_serpapi(fixture: fixture, status: upstream_status)

        post "/api/v1/keywords/#{keyword.id}/searches"

        expect(response).to have_http_status(http_status)
        expect(json["error"]).to include("code" => "search_failed")
        expect(json["error"]["details"]["category"]).to eq(category)

        run = SearchRun.find(json["error"]["details"]["run_id"])
        expect(run).to have_attributes(status: "failed", error_category: category, http_status: upstream_status)
      end
    end

    it "returns 504 and records a timeout when SerpApi is too slow" do
      stub_request(:get, /serpapi.com/).to_timeout

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:gateway_timeout)
      expect(SearchRun.last).to have_attributes(status: "failed", error_category: "timeout")
    end

    it "returns 502 for a network failure and keeps the last good snapshot" do
      stub_serpapi(fixture: "success")
      post "/api/v1/keywords/#{keyword.id}/searches"
      good_run_id = json["data"]["id"]

      stub_request(:get, /serpapi.com/).to_raise(Errno::ECONNREFUSED)
      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:bad_gateway)
      expect(SearchRun.find(good_run_id)).to have_attributes(status: "succeeded")
      expect(RankSnapshot.where(keyword: keyword).pluck(:rank)).to eq([ 2 ])
    end

    it "returns 502 for malformed JSON from the provider" do
      stub_serpapi(body: "<html>oops</html>")

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:bad_gateway)
      expect(json["error"]["details"]["category"]).to eq("schema")
    end

    it "returns 404 for an unknown keyword without calling SerpApi" do
      stub = stub_serpapi(fixture: "success")

      post "/api/v1/keywords/0/searches"

      expect(response).to have_http_status(:not_found)
      expect(stub).not_to have_been_requested
    end

    it "allows searching an inactive keyword manually" do
      keyword.update!(active: false)
      stub_serpapi(fixture: "success")

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:created)
    end
  end

  describe "budget", env: { "SERPAPI_API_KEY" => "request-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "2" } do
    it "returns 429 once the daily budget is spent and never calls SerpApi again" do
      stub = stub_serpapi(fixture: "success")

      2.times { post "/api/v1/keywords/#{keyword.id}/searches" }
      expect(response).to have_http_status(:created)

      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:too_many_requests)
      expect(json["error"]).to include("code" => "search_budget_exceeded")
      expect(json["error"]["details"]).to eq("limit" => 2, "used" => 2)
      expect(stub).to have_been_requested.twice
      expect(SearchRun.count).to eq(2)
    end
  end

  describe "without credentials" do
    it "returns 503 and makes no request when the key is the placeholder", env: { "SERPAPI_API_KEY" => "replace_me" } do
      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:service_unavailable)
      expect(json["error"]["code"]).to eq("search_provider_not_configured")
      expect(a_request(:any, /serpapi.com/)).not_to have_been_made
      expect(SearchRun.count).to eq(0)
    end

    it "returns 503 when the key is missing", env: { "SERPAPI_API_KEY" => nil } do
      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe "GET /api/v1/keywords/:keyword_id/searches" do
    it "lists runs newest first with pagination and no result bodies" do
      old_run = create(:search_run, keyword: keyword, created_at: 2.hours.ago)
      new_run = create(:search_run, keyword: keyword, created_at: 1.hour.ago, status: "failed", error_category: "timeout")
      create(:search_run) # another keyword's run

      get "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |r| r["id"] }).to eq([ new_run.id, old_run.id ])
      expect(json["data"].first).to include("status" => "failed", "error_category" => "timeout")
      expect(json["data"].first).not_to have_key("results")
      expect(json["meta"]).to eq("page" => 1, "per_page" => 25, "total_count" => 2, "total_pages" => 1)
    end

    it "returns an empty list for a keyword without runs" do
      get "/api/v1/keywords/#{keyword.id}/searches"

      expect(json["data"]).to eq([])
    end

    it "returns 404 for an unknown keyword" do
      get "/api/v1/keywords/0/searches"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/keywords/:keyword_id/searches/:id" do
    it "returns one run with its results" do
      run = create(:search_run, keyword: keyword)
      create(:search_result, search_run: run, position: 2, url: "https://b.example.com/")
      create(:search_result, search_run: run, position: 1, url: "https://a.example.com/")

      get "/api/v1/keywords/#{keyword.id}/searches/#{run.id}"

      expect(response).to have_http_status(:ok)
      expect(json["data"]["results"].map { |r| r["position"] }).to eq([ 1, 2 ])
    end

    it "does not return a run that belongs to another keyword" do
      other_run = create(:search_run)

      get "/api/v1/keywords/#{keyword.id}/searches/#{other_run.id}"

      expect(response).to have_http_status(:not_found)
    end
  end
end
