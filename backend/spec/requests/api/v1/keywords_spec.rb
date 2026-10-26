require "rails_helper"

RSpec.describe "Api::V1::Keywords", type: :request do
  # A method, not a memoized let: examples that send several requests must read the latest response.
  def json
    response.parsed_body
  end
  let(:valid_params) do
    { keyword: { query: "senior react developer", country: "ph", language: "en",
                 location: "Manila", target_domain: "https://www.example.com/jobs", schedule: "daily" } }
  end

  describe "GET /api/v1/keywords" do
    it "returns an empty page when there are no keywords" do
      get "/api/v1/keywords"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to eq([])
      expect(json["meta"]).to eq("page" => 1, "per_page" => 25, "total_count" => 0, "total_pages" => 0)
    end

    it "lists keywords newest first with only public fields" do
      older = create(:keyword, query: "older", created_at: 2.days.ago)
      newer = create(:keyword, query: "newer", created_at: 1.day.ago)

      get "/api/v1/keywords"

      expect(json["data"].map { |k| k["id"] }).to eq([ newer.id, older.id ])
      expect(json["data"].first.keys).to match_array(
        %w[id query engine country language location target_domain active schedule created_at updated_at freshness activity]
      )
    end

    it "includes at-a-glance activity: recent runs and the current rank" do
      keyword = create(:keyword, target_domain: "example.com")
      run = create(:search_run, keyword: keyword, upstream_latency_ms: 250)
      create(:rank_snapshot, keyword: keyword, search_run: run, rank: 4, target_domain: "example.com")
      create(:keyword, query: "quiet")

      get "/api/v1/keywords"

      busy = json["data"].find { |k| k["id"] == keyword.id }
      quiet = json["data"].find { |k| k["id"] != keyword.id }
      expect(busy["activity"]["recent_runs"].map { |r| r["id"] }).to eq([ run.id ])
      expect(busy["activity"]["latency_ms"]).to eq("samples" => 1, "p95" => 250, "max" => 250)
      expect(busy["activity"]["rank"]).to include("rank" => 4, "found" => true)
      expect(busy["activity"]["rank"]["comparison"]["status"]).to eq("baseline")
      expect(quiet["activity"]).to eq("recent_runs" => [], "latency_ms" => { "samples" => 0, "p95" => nil, "max" => nil }, "rank" => nil)
    end

    it "paginates and reports totals" do
      create_list(:keyword, 5)

      get "/api/v1/keywords", params: { page: 2, per_page: 2 }

      expect(json["data"].size).to eq(2)
      expect(json["meta"]).to eq("page" => 2, "per_page" => 2, "total_count" => 5, "total_pages" => 3)
    end

    it "returns an empty page beyond the last page" do
      create_list(:keyword, 2)

      get "/api/v1/keywords", params: { page: 9, per_page: 2 }

      expect(json["data"]).to eq([])
      expect(json["meta"]["total_count"]).to eq(2)
    end

    it "caps per_page at 100 and treats a non-numeric page as 1" do
      get "/api/v1/keywords", params: { per_page: 5000, page: "abc" }

      expect(json["meta"]).to include("per_page" => 100, "page" => 1)
    end

    it "falls back to defaults for negative page and per_page" do
      get "/api/v1/keywords", params: { per_page: -3, page: -1 }

      expect(json["meta"]).to include("per_page" => 25, "page" => 1)
    end

    it "filters by active state" do
      active = create(:keyword, active: true)
      create(:keyword, active: false)

      get "/api/v1/keywords", params: { active: "true" }

      expect(json["data"].map { |k| k["id"] }).to eq([ active.id ])
    end
  end

  describe "POST /api/v1/keywords" do
    it "creates a keyword and normalizes its fields" do
      expect { post "/api/v1/keywords", params: valid_params, as: :json }
        .to change(Keyword, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to eq("/api/v1/keywords/#{json['data']['id']}")
      expect(json["data"]).to include(
        "query" => "senior react developer", "engine" => "google", "country" => "ph",
        "language" => "en", "location" => "Manila", "target_domain" => "example.com",
        "active" => true, "schedule" => "daily"
      )
    end

    it "applies defaults for engine, active, and schedule" do
      post "/api/v1/keywords", params: { keyword: { query: "react", country: "us", language: "en" } }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("engine" => "google", "active" => true, "schedule" => "manual",
                                      "location" => nil, "target_domain" => nil)
    end

    it "accepts attributes without the wrapping keyword key" do
      post "/api/v1/keywords", params: { query: "react", country: "us", language: "en" }, as: :json

      expect(response).to have_http_status(:created)
    end

    it "returns 422 with field errors for invalid input" do
      post "/api/v1/keywords",
           params: { keyword: { query: "", engine: "bing", country: "zz", language: "en", target_domain: "localhost" } },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("validation_failed")
      expect(json["error"]["details"].keys).to include("query", "engine", "country", "target_domain")
    end

    it "returns 422 for a duplicate with the same search settings" do
      create(:keyword, query: "react", country: "us", language: "en")

      post "/api/v1/keywords", params: { keyword: { query: "react", country: "us", language: "en" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["details"]["query"].join).to include("already exists")
    end

    it "returns 422 once the keyword limit is reached" do
      stub_const("Keyword::DEFAULT_MAX_KEYWORDS", 1)
      create(:keyword)

      post "/api/v1/keywords", params: valid_params, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["details"]["base"].join).to include("keyword limit reached")
    end

    it "ignores attempts to set protected attributes" do
      post "/api/v1/keywords",
           params: { keyword: { query: "react", country: "us", language: "en", id: 999, created_at: "2000-01-01" } },
           as: :json

      expect(response).to have_http_status(:created)
      expect(json["data"]["id"]).not_to eq(999)
      expect(Time.zone.parse(json["data"]["created_at"])).to be > 1.day.ago
    end

    it "returns 400 when the keyword payload is missing" do
      post "/api/v1/keywords", params: {}, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json["error"]["code"]).to eq("bad_request")
    end

    it "returns 400 for malformed JSON" do
      post "/api/v1/keywords", params: "{not json", headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:bad_request)
      expect(json["error"]["code"]).to eq("bad_request")
    end

    it "returns 409 when the database unique index wins a race" do
      allow_any_instance_of(Keyword).to receive(:save).and_raise(ActiveRecord::RecordNotUnique) # rubocop:disable RSpec/AnyInstance

      post "/api/v1/keywords", params: valid_params, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["error"]["code"]).to eq("conflict")
    end
  end

  describe "GET /api/v1/keywords/:id" do
    it "returns the keyword" do
      keyword = create(:keyword, target_domain: "example.com")

      get "/api/v1/keywords/#{keyword.id}"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("id" => keyword.id, "target_domain" => "example.com")
    end

    it "returns 404 for an unknown id" do
      get "/api/v1/keywords/0"

      expect(response).to have_http_status(:not_found)
      expect(json["error"]["code"]).to eq("not_found")
    end

    it "returns 404 for a non-numeric id" do
      get "/api/v1/keywords/abc"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/keywords/:id" do
    let!(:keyword) { create(:keyword, query: "react", active: true) }

    it "updates the permitted fields" do
      patch "/api/v1/keywords/#{keyword.id}",
            params: { keyword: { active: false, schedule: "weekly", target_domain: "Blog.Example.com" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("active" => false, "schedule" => "weekly", "target_domain" => "blog.example.com")
    end

    it "clears optional fields with null or blank" do
      keyword.update!(location: "Manila", target_domain: "example.com")

      patch "/api/v1/keywords/#{keyword.id}", params: { keyword: { location: nil, target_domain: "" } }, as: :json

      expect(json["data"]).to include("location" => nil, "target_domain" => nil)
    end

    it "returns 422 and leaves the record unchanged on invalid input" do
      patch "/api/v1/keywords/#{keyword.id}", params: { keyword: { schedule: "every_minute" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["details"].keys).to include("schedule")
      expect(keyword.reload.schedule).to eq("manual")
    end

    it "returns 422 when the update would duplicate another keyword" do
      create(:keyword, query: "vue", country: "us", language: "en")

      patch "/api/v1/keywords/#{keyword.id}", params: { keyword: { query: "vue" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for an unknown id" do
      patch "/api/v1/keywords/0", params: { keyword: { active: false } }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/keywords/:id" do
    it "deletes the keyword and its history" do
      snapshot = create(:rank_snapshot)

      expect { delete "/api/v1/keywords/#{snapshot.keyword_id}" }
        .to change(Keyword, :count).by(-1)
        .and change(SearchRun, :count).by(-1)
        .and change(RankSnapshot, :count).by(-1)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
    end

    it "returns 404 for an unknown id" do
      delete "/api/v1/keywords/0"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "freshness" do
    it "is no_data for a new keyword" do
      post "/api/v1/keywords", params: valid_params, as: :json

      expect(json["data"]["freshness"]).to eq(
        "state" => "no_data", "reason" => nil, "last_success_at" => nil, "last_attempt_status" => nil, "last_attempt_at" => nil
      )
    end

    it "reports fresh and stale states in the list and on a single keyword" do
      fresh = create(:keyword, query: "fresh one")
      create(:search_run, keyword: fresh)
      stale = create(:keyword, query: "stale one")
      create(:search_run, keyword: stale, finished_at: 2.hours.ago)
      create(:search_run, :failed, keyword: stale, finished_at: 1.hour.ago)

      get "/api/v1/keywords"
      states = json["data"].to_h { |k| [ k["query"], k["freshness"]["state"] ] }
      expect(states).to eq("fresh one" => "fresh", "stale one" => "stale")

      get "/api/v1/keywords/#{stale.id}"
      expect(json["data"]["freshness"]).to include("state" => "stale", "reason" => "last_attempt_failed", "last_attempt_status" => "failed")
    end
  end
end
