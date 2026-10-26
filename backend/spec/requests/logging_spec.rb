require "rails_helper"

# What a person types is their business: the sentence they ask Laya about, the keywords they track, and the
# domains they follow must not end up in the application log, where logs are copied, shipped, and kept. The
# log may carry ids, outcomes, and timings. These capture everything Rails logs at debug level (the most
# verbose setting, which includes the SQL with its values) while a person uses the API.
RSpec.describe "What the log contains", type: :request,
                                          env: { "SERPAPI_API_KEY" => "log-spec-key-123456", "SEARCH_MAX_REQUESTS_PER_DAY" => "20", "LAYA_ENABLED" => "true" } do
  include ActiveJob::TestHelper

  let(:io) { StringIO.new }
  let(:capture) { ActiveSupport::Logger.new(io) }
  let(:log) { io.string }

  # Distinctive strings that cannot occur in the log by accident.
  let(:marker_query) { "zq-marker-query-7781" }
  let(:marker_domain) { "marker-domain-7781.example" }
  let(:marker_location) { "Marker Town 7781" }
  let(:marker_sentence) { "Where does #{marker_domain} rank for '#{marker_query}' in the Philippines? marker-words-7781" }

  around do |example|
    Rails.logger.broadcast_to(capture)
    example.run
  ensure
    Rails.logger.stop_broadcasting_to(capture)
  end

  before { IntentsControllerReset.call }

  it "does not contain the sentence of a planning request, which proves the capture works by showing the request itself" do
    stub_laya(intent: "organic_rank_tracking", confidence: 0.95)

    post "/api/v1/intent/plan", params: { text: marker_sentence }, as: :json

    expect(response).to have_http_status(:created)
    expect(log).to include("POST", "/api/v1/intent/plan") # the request is logged, so an empty log cannot make this pass
    expect(log).not_to include("marker-words-7781", marker_query, marker_domain)
  end

  it "does not contain the keyword a person creates or edits" do
    post "/api/v1/keywords", params: { keyword: { query: marker_query, country: "ph", language: "en", location: marker_location, target_domain: marker_domain } }, as: :json
    id = response.parsed_body["data"]["id"]
    patch "/api/v1/keywords/#{id}", params: { keyword: { query: "#{marker_query} edited" } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(log).to include("POST", "/api/v1/keywords")
    expect(log).not_to include(marker_query, marker_domain, marker_location)
  end

  it "does not contain what a person types when confirming or completing a plan" do
    stub_laya(intent: "organic_rank_tracking", confidence: 0.95)
    stub_serpapi(fixture: "success")
    post "/api/v1/intent/plan", params: { text: "Where does example.com rank?" }, as: :json
    plan_id = response.parsed_body["data"]["id"]

    perform_enqueued_jobs do
      post "/api/v1/intent/plan/#{plan_id}/confirm", params: { plan: { query: marker_query, country: "ph", language: "en", target_domain: marker_domain } }, as: :json
    end

    expect(response).to have_http_status(:ok)
    expect(log).to include("/confirm")
    expect(log).not_to include(marker_query, marker_domain)
  end

  it "does not contain the search terms while a search runs, and never the SerpApi key" do
    keyword = create(:keyword, query: marker_query, target_domain: marker_domain, location: marker_location, country: "ph")
    stub_serpapi(fixture: "success")

    perform_enqueued_jobs { post "/api/v1/keywords/#{keyword.id}/searches" }

    expect(log).to include("search_attempt") # our own structured line is there
    expect(log).not_to include(marker_query, marker_domain, marker_location, "log-spec-key-123456")
  end

  it "keeps ids, outcomes, and timings, so the log is still useful for finding out what happened" do
    stub_laya(intent: "organic_rank_tracking", confidence: 0.95)

    post "/api/v1/intent/plan", params: { text: marker_sentence }, as: :json

    expect(log).to match(/intent_plan .*outcome=/)
    expect(log).to match(/Completed 201/)
  end
end
