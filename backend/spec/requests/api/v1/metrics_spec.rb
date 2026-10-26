require "rails_helper"

RSpec.describe "Api::V1::Metrics", type: :request, env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "20", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
  def json
    response.parsed_body
  end

  describe "GET /api/v1/metrics/summary" do
    it "returns the summary for the default 24h window" do
      run = create(:search_run, upstream_latency_ms: 120)
      create(:search_run, :cache_hit, keyword: run.keyword, source_run: run)
      create(:search_run, :failed, error_category: "timeout", upstream_latency_ms: 15_000)

      get "/api/v1/metrics/summary"

      expect(response).to have_http_status(:ok)
      data = json["data"]
      expect(data.keys).to match_array(%w[window requests upstream cache errors budget keywords queue])
      expect(data["window"]["name"]).to eq("24h")
      expect(data["requests"]["total"]).to eq(3)
      expect(data["errors"]).to eq("timeout" => 1)
      expect(data["cache"]).to include("hits" => 1, "misses" => 2)
      expect(data["upstream"]["latency_ms"]).to include("samples" => 2, "max" => 15_000)
      expect(data["budget"]).to include("daily_limit" => 20)
    end

    it "accepts every documented window" do
      MetricsSummary::WINDOWS.each_key do |window|
        get "/api/v1/metrics/summary", params: { window: window }

        expect(response).to have_http_status(:ok)
        expect(json["data"]["window"]["name"]).to eq(window)
      end
    end

    it "rejects an unknown window and lists the allowed ones" do
      get "/api/v1/metrics/summary", params: { window: "1y" }

      expect(response).to have_http_status(:bad_request)
      expect(json["error"]).to include("code" => "bad_request")
      expect(json["error"]["details"]["allowed"]).to eq(%w[1h 24h 7d 30d])
    end

    it "is valid on an empty database" do
      get "/api/v1/metrics/summary"

      expect(response).to have_http_status(:ok)
      expect(json["data"]["upstream"]["success_rate"]).to be_nil
      expect(json["data"]["cache"]["hit_rate"]).to be_nil
    end

    it "exposes no search terms, error text, or credentials" do
      create(:search_run, :failed, request_metadata: { "query" => "private words", "error_message" => "Invalid API key abc123" })

      get "/api/v1/metrics/summary"

      expect(response.body).not_to include("private words")
      expect(response.body).not_to include("abc123")
    end
  end
end
