require "rails_helper"

RSpec.describe "GET /health", type: :request do
  context "when the database is reachable" do
    it "returns 200 with status ok" do
      get "/health"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "ok", "database" => "up")
    end
  end

  context "when the database is unreachable" do
    before do
      allow(ActiveRecord::Base.connection_pool)
        .to receive(:with_connection)
        .and_raise(ActiveRecord::ConnectionNotEstablished, "secret connection detail")
    end

    it "returns 503 with status degraded" do
      get "/health"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq("status" => "degraded", "database" => "down")
    end

    it "does not leak the underlying error message" do
      get "/health"

      expect(response.body).not_to include("secret connection detail")
    end
  end
end
