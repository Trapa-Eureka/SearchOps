require "rails_helper"

RSpec.describe "Api::V1::Searches", type: :request do
  include ActiveJob::TestHelper

  # A method, not a memoized let: examples that send several requests must read the latest response.
  def json
    response.parsed_body
  end
  let(:api_key) { "request-spec-key-123456" }
  let(:keyword) do
    create(:keyword, query: "react developer", country: "ph", language: "en", location: "Manila", target_domain: "example.com")
  end
  let(:base_env) do
    { "SERPAPI_API_KEY" => api_key, "SEARCH_MAX_REQUESTS_PER_DAY" => "50", "SEARCH_CACHE_TTL_SECONDS" => "3600" }
  end

  # Starts a search and lets the queued job (and any retries) run inline, so the whole chain
  # request -> job -> real SerpApi adapter -> database is exercised. Only HTTP to SerpApi is stubbed.
  def search!(kw = keyword, params: {})
    perform_enqueued_jobs { post "/api/v1/keywords/#{kw.id}/searches", params: params }
    response
  end

  def fetch_run(id, kw = keyword)
    get "/api/v1/keywords/#{kw.id}/searches/#{id}"
    response.parsed_body["data"]
  end

  context "with credentials", env: { "SERPAPI_API_KEY" => "request-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "50",
                                     "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
    describe "POST /api/v1/keywords/:keyword_id/searches" do
      it "queues the search without calling SerpApi inside the request" do
        stub = stub_serpapi(fixture: "success")

        post "/api/v1/keywords/#{keyword.id}/searches"

        expect(response).to have_http_status(:accepted)
        expect(stub).not_to have_been_requested
        expect(ExecuteSearchJob).to have_been_enqueued.exactly(:once)
        data = json["data"]
        expect(json["meta"]).to eq("outcome" => "enqueued")
        expect(data).to include("status" => "queued", "attempts" => 0, "upstream_calls" => 0, "triggered_by" => "manual")
        expect(data).not_to have_key("results")
        expect(response.headers["Location"]).to eq("/api/v1/keywords/#{keyword.id}/searches/#{data['id']}")
      end

      it "runs the job and exposes normalized results and the target rank" do
        stub = stub_serpapi(fixture: "success")

        search!
        run = fetch_run(json["data"]["id"])

        expect(stub).to have_been_requested.once
        expect(run).to include("status" => "succeeded", "http_status" => 200, "error_category" => nil, "result_count" => 5,
                               "attempts" => 1, "upstream_calls" => 1, "cache_source" => "none")
        expect(run["upstream_latency_ms"]).to be >= 0
        expect(run["rank"]).to eq("target_domain" => "example.com", "rank" => 2, "found" => true)
        expect(run["request"]).to include("engine" => "google", "query" => "react developer", "country" => "ph",
                                          "language" => "en", "location" => "Manila", "search_id" => "fixture-success-1")
        expect(run["results"].map { |r| r["position"] }).to eq([ 1, 2, 3, 4, 5 ])
        expect(run["results"][1]).to eq(
          "position" => 2, "title" => "React developer jobs", "url" => "https://www.example.com/jobs/react",
          "display_domain" => "example.com", "snippet" => "Find remote React roles."
        )
      end

      it "sends the keyword's settings to SerpApi" do
        stub = stub_request(:get, "https://serpapi.com/search")
               .with(query: hash_including("q" => "react developer", "gl" => "ph", "hl" => "en", "location" => "Manila", "engine" => "google"))
               .to_return(status: 200, body: serpapi_fixture("success"))

        search!

        expect(stub).to have_been_requested.once
      end

      it "never exposes the API key" do
        stub_serpapi(fixture: "invalid_api_key", status: 401)

        search!
        fetch_run(json["data"]["id"])

        expect(response.body).not_to include(api_key)
        expect(SearchRun.last.request_metadata.to_json).not_to include(api_key)
      end

      it "treats an empty SERP as a successful run with a null rank" do
        stub_serpapi(fixture: "empty")

        search!
        run = fetch_run(json["data"]["id"])

        expect(run).to include("status" => "succeeded", "result_count" => 0, "empty_results" => true, "results" => [])
        expect(run["rank"]).to eq("target_domain" => "example.com", "rank" => nil, "found" => false)
      end

      it "reports a null rank when the target domain is not in the results" do
        keyword.update!(target_domain: "absent.org")
        stub_serpapi(fixture: "success")

        search!

        expect(fetch_run(json["data"]["id"])["rank"]).to include("rank" => nil, "found" => false)
      end

      it "skips the rank snapshot when the keyword has no target domain" do
        keyword.update!(target_domain: nil)
        stub_serpapi(fixture: "success")

        search!

        expect(fetch_run(json["data"]["id"])["rank"]).to be_nil
        expect(RankSnapshot.count).to eq(0)
      end

      it "allows searching an inactive keyword manually" do
        keyword.update!(active: false)
        stub_serpapi(fixture: "success")

        search!

        expect(response).to have_http_status(:accepted)
        expect(SearchRun.last.status).to eq("succeeded")
      end

      it "returns 404 for an unknown keyword without queuing or calling SerpApi" do
        stub = stub_serpapi(fixture: "success")

        post "/api/v1/keywords/0/searches"

        expect(response).to have_http_status(:not_found)
        expect(stub).not_to have_been_requested
        expect(ExecuteSearchJob).not_to have_been_enqueued
      end
    end

    describe "caching" do
      it "answers a repeat request from the local cache without calling SerpApi" do
        stub = stub_serpapi(fixture: "success")
        search!
        first_id = json["data"]["id"]

        post "/api/v1/keywords/#{keyword.id}/searches"

        expect(response).to have_http_status(:ok)
        expect(json["meta"]).to eq("outcome" => "cache_hit")
        data = json["data"]
        expect(data["id"]).not_to eq(first_id)
        expect(data).to include("status" => "succeeded", "cache_source" => "app", "upstream_calls" => 0, "attempts" => 0,
                                "result_count" => 5)
        expect(data["cache"]).to include("hit" => true, "source_run_id" => first_id)
        expect(data["cache"]["age_seconds"]).to be >= 0
        expect(data["results"].map { |r| r["position"] }).to eq([ 1, 2, 3, 4, 5 ])
        expect(data["rank"]).to eq("target_domain" => "example.com", "rank" => 2, "found" => true)
        expect(stub).to have_been_requested.once
        expect(RankSnapshot.count).to eq(1)
        expect(ExecuteSearchJob).not_to have_been_enqueued
      end

      it "serves the cache even if the daily budget is spent",
         env: { "SERPAPI_API_KEY" => "request-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "1", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
        stub_serpapi(fixture: "success")
        search!

        post "/api/v1/keywords/#{keyword.id}/searches"

        expect(response).to have_http_status(:ok)
      end

      it "calls SerpApi again with ?refresh=true" do
        stub = stub_serpapi(fixture: "success")
        search!

        search!(params: { refresh: "true" })

        expect(response).to have_http_status(:accepted)
        expect(stub).to have_been_requested.twice
        expect(SearchRun.where(cache_source: "none").count).to eq(2)
      end

      it "calls SerpApi again when the cache is disabled",
         env: { "SERPAPI_API_KEY" => "request-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "50", "SEARCH_CACHE_TTL_SECONDS" => "0" } do
        stub = stub_serpapi(fixture: "success")

        2.times { search! }

        expect(stub).to have_been_requested.twice
      end
    end

    describe "duplicate requests" do
      it "returns the run already in flight instead of starting another" do
        stub_serpapi(fixture: "success")

        post "/api/v1/keywords/#{keyword.id}/searches"
        first_id = json["data"]["id"]
        post "/api/v1/keywords/#{keyword.id}/searches"

        expect(response).to have_http_status(:accepted)
        expect(json["meta"]).to eq("outcome" => "deduplicated")
        expect(json["data"]["id"]).to eq(first_id)
        expect(SearchRun.count).to eq(1)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)
      end

      it "calls SerpApi once even if the queued job is delivered twice" do
        stub = stub_serpapi(fixture: "success")
        post "/api/v1/keywords/#{keyword.id}/searches"
        run_id = json["data"]["id"]

        2.times { ExecuteSearchJob.perform_now(run_id) }

        expect(stub).to have_been_requested.once
      end
    end

    describe "failures" do
      {
        [ 401, "invalid_api_key" ] => "auth",
        [ 400, "missing_query" ] => "invalid_request",
        [ 429, "out_of_searches" ] => "quota"
      }.each do |(upstream_status, fixture), category|
        it "records #{category} as a failed run after a single attempt" do
          stub = stub_serpapi(fixture: fixture, status: upstream_status)

          search!
          run = fetch_run(json["data"]["id"])

          expect(run).to include("status" => "failed", "error_category" => category, "http_status" => upstream_status,
                                 "attempts" => 1, "upstream_calls" => 1)
          expect(run["error_message"]).to be_present
          expect(stub).to have_been_requested.once
        end
      end

      it "retries a persistent 503 up to the attempt limit and then fails" do
        stub = stub_serpapi(fixture: "server_error", status: 503)

        search!
        run = fetch_run(json["data"]["id"])

        expect(stub).to have_been_requested.times(3)
        expect(run).to include("status" => "failed", "error_category" => "upstream", "attempts" => 3, "upstream_calls" => 3)
        expect(run["attempt_log"].map { |entry| entry["attempt"] }).to eq([ 1, 2, 3 ])
      end

      it "recovers when a retry succeeds" do
        stub_request(:get, /serpapi.com/)
          .to_return({ status: 503, body: serpapi_fixture("server_error") }, { status: 200, body: serpapi_fixture("success") })

        search!
        run = fetch_run(json["data"]["id"])

        expect(run).to include("status" => "succeeded", "attempts" => 2, "upstream_calls" => 2, "error_category" => nil)
        expect(run["attempt_log"].size).to eq(1)
        expect(run["results"].size).to eq(5)
      end

      it "retries timeouts and network errors" do
        stub_request(:get, /serpapi.com/).to_timeout.then.to_raise(Errno::ECONNREFUSED).then
                                         .to_return(status: 200, body: serpapi_fixture("success"))

        search!
        run = fetch_run(json["data"]["id"])

        expect(run).to include("status" => "succeeded", "attempts" => 3)
        expect(run["attempt_log"].map { |entry| entry["category"] }).to eq(%w[timeout network])
      end

      it "records a timeout as a failed run once retries are used up" do
        stub_request(:get, /serpapi.com/).to_timeout

        search!

        expect(fetch_run(json["data"]["id"])).to include("status" => "failed", "error_category" => "timeout", "attempts" => 3)
      end

      it "records malformed JSON as a schema failure without retrying" do
        stub = stub_serpapi(body: "<html>oops</html>")

        search!

        expect(fetch_run(json["data"]["id"])).to include("status" => "failed", "error_category" => "schema", "attempts" => 1)
        expect(stub).to have_been_requested.once
      end

      it "keeps the last good data, marks the keyword stale, and does not hide the failure" do
        stub_serpapi(fixture: "success")
        search!
        good_id = json["data"]["id"]

        stub_serpapi(fixture: "invalid_api_key", status: 401)
        search!(params: { refresh: "true" })
        failed_id = json["data"]["id"]

        expect(fetch_run(failed_id)).to include("status" => "failed")
        expect(fetch_run(good_id)).to include("status" => "succeeded", "rank" => { "target_domain" => "example.com", "rank" => 2, "found" => true })

        get "/api/v1/keywords/#{keyword.id}/rank_history"
        expect(json["data"].map { |s| s["rank"] }).to eq([ 2 ])
        expect(json["meta"]["freshness"]).to include("state" => "stale", "reason" => "last_attempt_failed", "last_attempt_status" => "failed")

        get "/api/v1/keywords/#{keyword.id}"
        expect(json["data"]["freshness"]).to include("state" => "stale", "reason" => "last_attempt_failed")
      end
    end

    describe "the daily budget" do
      it "returns 429 once spent, without creating a run or calling SerpApi",
         env: { "SERPAPI_API_KEY" => "request-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "2", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
        stub = stub_serpapi(fixture: "success")

        2.times { search!(params: { refresh: "true" }) }
        expect(response).to have_http_status(:accepted)

        post "/api/v1/keywords/#{keyword.id}/searches", params: { refresh: "true" }

        expect(response).to have_http_status(:too_many_requests)
        expect(json["error"]).to include("code" => "search_budget_exceeded")
        expect(json["error"]["details"]).to eq("limit" => 2, "used" => 2)
        expect(stub).to have_been_requested.twice
        expect(SearchRun.count).to eq(2)
      end

      it "counts retries against the budget",
         env: { "SERPAPI_API_KEY" => "request-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "2", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
        stub = stub_serpapi(fixture: "server_error", status: 503)

        search!
        run = fetch_run(json["data"]["id"])

        expect(stub).to have_been_requested.twice
        expect(run).to include("status" => "failed", "error_category" => "budget", "upstream_calls" => 2)
      end
    end

    describe "GET /api/v1/keywords/:keyword_id/searches" do
      it "lists runs newest first with pagination and no result bodies" do
        old_run = create(:search_run, keyword: keyword, created_at: 2.hours.ago)
        new_run = create(:search_run, :failed, keyword: keyword, created_at: 1.hour.ago, error_category: "timeout")
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
      it "returns one run with its results ordered by position" do
        run = create(:search_run, keyword: keyword)
        create(:search_result, search_run: run, position: 2, url: "https://b.example.com/")
        create(:search_result, search_run: run, position: 1, url: "https://a.example.com/")

        get "/api/v1/keywords/#{keyword.id}/searches/#{run.id}"

        expect(response).to have_http_status(:ok)
        expect(json["data"]["results"].map { |r| r["position"] }).to eq([ 1, 2 ])
      end

      it "returns the results of the source run for a cache hit" do
        source = create(:search_run, keyword: keyword)
        create(:search_result, search_run: source, position: 1, url: "https://a.example.com/")
        hit = create(:search_run, :cache_hit, keyword: keyword, source_run: source)

        get "/api/v1/keywords/#{keyword.id}/searches/#{hit.id}"

        expect(json["data"]["results"].map { |r| r["url"] }).to eq([ "https://a.example.com/" ])
        expect(json["data"]["cache"]).to include("hit" => true, "source_run_id" => source.id)
      end

      it "does not return a run that belongs to another keyword" do
        other_run = create(:search_run)

        get "/api/v1/keywords/#{keyword.id}/searches/#{other_run.id}"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "without credentials" do
    it "returns 503 and makes no request when the key is the placeholder", env: { "SERPAPI_API_KEY" => "replace_me" } do
      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:service_unavailable)
      expect(json["error"]["code"]).to eq("search_provider_not_configured")
      expect(a_request(:any, /serpapi.com/)).not_to have_been_made
      expect(SearchRun.count).to eq(0)
      expect(ExecuteSearchJob).not_to have_been_enqueued
    end

    it "returns 503 when the key is missing", env: { "SERPAPI_API_KEY" => nil } do
      post "/api/v1/keywords/#{keyword.id}/searches"

      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
