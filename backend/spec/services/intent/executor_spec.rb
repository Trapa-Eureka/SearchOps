require "rails_helper"

RSpec.describe Intent::Executor, env: { "SERPAPI_API_KEY" => "executor-spec-key-1234", "SEARCH_MAX_REQUESTS_PER_DAY" => "20", "SEARCH_CACHE_TTL_SECONDS" => "3600" } do
  subject(:executor) { described_class.new }

  let(:rank_plan) do
    { "intent" => "organic_rank_tracking", "engine" => "google", "query" => "react developer jobs", "country" => "ph",
      "language" => "en", "target_domain" => "example.com", "compare_previous" => false, "only_new" => false }
  end

  def planned(plan: rank_plan, outcome: "planned", reason: nil, **attrs)
    IntentRequest.create!(original_text: "text", plan: plan, outcome: outcome, fallback_reason: reason, **attrs)
  end

  describe "confirming a ready rank-tracking plan" do
    it "creates the keyword, queues one search, and records what happened" do
      request = planned

      expect { executor.call(request) }.to change(Keyword, :count).by(1).and change(SearchRun, :count).by(1)

      keyword = Keyword.last
      expect(keyword).to have_attributes(query: "react developer jobs", engine: "google", country: "ph", language: "en",
                                         target_domain: "example.com", active: true, schedule: "manual")
      expect(ExecuteSearchJob).to have_been_enqueued.exactly(:once)
      request.reload
      expect(request).to have_attributes(outcome: "executed")
      expect(request.confirmed_at).to be_present
      expect(request.execution).to eq("kind" => "search", "keyword_id" => keyword.id, "keyword_created" => true,
                                      "run_id" => SearchRun.last.id, "search_outcome" => "enqueued")
    end

    it "reuses an existing identical keyword" do
      existing = create(:keyword, query: "react developer jobs", country: "ph", language: "en", target_domain: "example.com")
      request = planned

      expect { executor.call(request) }.not_to change(Keyword, :count)

      expect(request.reload.execution).to include("keyword_id" => existing.id, "keyword_created" => false)
    end

    it "answers from the cache when a fresh result exists, without queuing" do
      keyword = create(:keyword, query: "react developer jobs", country: "ph", language: "en", target_domain: "example.com")
      fingerprint = SearchFingerprint.call(SearchProvider::Request.from_keyword(keyword))
      run = create(:search_run, keyword: keyword, fingerprint: fingerprint, finished_at: 5.minutes.ago)
      create(:rank_snapshot, keyword: keyword, search_run: run, target_domain: "example.com")
      request = planned

      executor.call(request)

      expect(request.reload.execution).to include("search_outcome" => "cache_hit")
      expect(ExecuteSearchJob).not_to have_been_enqueued
    end

    it "is idempotent: confirming twice does not search twice" do
      request = planned

      2.times { executor.call(request) }

      expect([ Keyword.count, SearchRun.count ]).to eq([ 1, 1 ])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)
    end

    it "is idempotent from a stale copy of the record too" do
      request = planned
      stale = IntentRequest.find(request.id)

      executor.call(request)
      executor.call(stale)

      expect(SearchRun.count).to eq(1)
    end
  end

  describe "edits made while confirming" do
    it "complete a plan that was missing fields" do
      incomplete = rank_plan.except("country", "language")
      request = planned(plan: incomplete, outcome: "needs_clarification", reason: "missing_fields")

      executor.call(request, { "country" => "jp", "language" => "ja" })

      expect(Keyword.last).to have_attributes(country: "jp", language: "ja")
      expect(request.reload.plan).to include("country" => "jp", "language" => "ja")
    end

    it "override suggested values and are normalized again" do
      request = planned

      executor.call(request, { "query" => "  vue   developer ", "target_domain" => "https://WWW.Other.org/x", "country" => "KR", "language" => "KO" })

      expect(Keyword.last).to have_attributes(query: "vue developer", target_domain: "other.org", country: "kr", language: "ko")
    end

    it "can switch the flags off" do
      request = planned(plan: rank_plan.merge("compare_previous" => true))

      executor.call(request, { "compare_previous" => false })

      expect(request.reload.plan["compare_previous"]).to be(false)
    end

    it "must still make the plan complete" do
      request = planned(plan: rank_plan.except("country", "language"), outcome: "needs_clarification", reason: "missing_fields")

      expect { executor.call(request) }.to raise_error(described_class::InvalidPlan) { |error| expect(error.missing).to eq(%w[country language]) }
      expect(request.reload.outcome).to eq("needs_clarification")
      expect([ Keyword.count, SearchRun.count ]).to eq([ 0, 0 ])
    end

    it "are validated like any plan: unknown fields, bad values, wrong types" do
      request = planned

      [ { "sql" => "DROP TABLE keywords" }, { "country" => "zz" }, { "target_domain" => "localhost" },
        { "query" => 5 }, { "compare_previous" => "true" }, { "engine" => "bing" }, { "keyword_id" => 99_999 } ].each do |edit|
        expect { executor.call(request, edit) }.to raise_error(described_class::InvalidPlan), "expected #{edit} to be rejected"
      end
      expect([ Keyword.count, SearchRun.count ]).to eq([ 0, 0 ])
    end

    it "cannot change the intent" do
      request = planned

      expect { executor.call(request, { "intent" => "search_history" }) }.to raise_error(described_class::InvalidPlan) { |error|
        expect(error.errors).to eq("intent" => "cannot_be_changed")
      }
    end

    it "must be an object" do
      expect { executor.call(planned, "country=jp") }.to raise_error(described_class::InvalidPlan)
    end

    it "accepts the same intent value explicitly" do
      expect { executor.call(planned, { "intent" => "organic_rank_tracking" }) }.not_to raise_error
    end
  end

  describe "plans that cannot be confirmed" do
    {
      "no plan (low confidence)" => [ nil, "needs_clarification", "low_confidence", "no_plan_to_confirm" ],
      "no plan (out of scope)" => [ nil, "unsupported", "out_of_scope", "no_plan_to_confirm" ],
      "no plan (classifier unavailable)" => [ nil, "unavailable", "laya_disabled", "no_plan_to_confirm" ]
    }.each do |name, (plan, outcome, reason, code)|
      it "refuses #{name}" do
        request = planned(plan: plan, outcome: outcome, reason: reason)

        expect { executor.call(request) }.to raise_error(described_class::NotConfirmable) { |error| expect(error.code).to eq(code) }
        expect([ Keyword.count, SearchRun.count ]).to eq([ 0, 0 ])
      end
    end

    it "refuses a job search because its engine is not implemented, even when edited to be complete" do
      job = { "intent" => "job_search", "engine" => "google_jobs", "query" => "react", "country" => "ph", "language" => "en" }
      request = planned(plan: job, outcome: "unsupported", reason: "engine_not_available")

      expect { executor.call(request, { "query" => "vue" }) }.to raise_error(described_class::NotConfirmable) { |error| expect(error.code).to eq("engine_not_available") }
      expect(Keyword.count).to eq(0)
    end

    it "refuses a job search that is still missing fields once edited to be complete" do
      job = { "intent" => "job_search", "engine" => "google_jobs", "query" => "react" }
      request = planned(plan: job, outcome: "needs_clarification", reason: "missing_fields")

      expect { executor.call(request, { "country" => "ph", "language" => "en" }) }.to raise_error(described_class::NotConfirmable) { |error|
        expect(error.code).to eq("engine_not_available")
      }
    end
  end

  describe "the daily budget and keyword limit" do
    it "leave the request unconfirmed so it can be retried", env: { "SEARCH_MAX_REQUESTS_PER_DAY" => "1" } do
      create(:search_run, upstream_calls: 1)
      request = planned

      expect { executor.call(request) }.to raise_error(SearchBudget::Exceeded)

      expect(request.reload).to have_attributes(outcome: "planned", confirmed_at: nil, execution: nil)
    end

    it "report a full keyword list as an invalid plan", env: { "SEARCH_MAX_KEYWORDS" => "1" } do
      create(:keyword)

      expect { executor.call(planned) }.to raise_error(described_class::InvalidPlan) { |error| expect(error.errors["base"]).to include("keyword limit reached") }
    end
  end

  describe "confirming a history request" do
    it "records the keyword and runs no search" do
      keyword = create(:keyword)
      request = planned(plan: { "intent" => "search_history", "engine" => "google", "keyword_id" => keyword.id, "compare_previous" => false, "only_new" => false })

      executor.call(request)

      expect(request.reload.execution).to eq("kind" => "history", "keyword_id" => keyword.id)
      expect(SearchRun.count).to eq(0)
      expect(ExecuteSearchJob).not_to have_been_enqueued
    end

    it "works for all keywords" do
      request = planned(plan: { "intent" => "search_history", "engine" => "google" })

      expect { executor.call(request) }.not_to raise_error
      expect(request.reload.execution).to eq("kind" => "history", "keyword_id" => nil)
    end
  end

  it "does not need the classifier at all" do
    expect(Intent::LayaClassifier).not_to receive(:from_env)

    executor.call(planned)
  end

  it "logs the confirmation without the sentence" do
    allow(Rails.logger).to receive(:info)
    request = planned(original_text: "very private sentence")

    executor.call(request)

    expect(Rails.logger).to have_received(:info).with(a_string_matching(/intent_confirmed request_id=#{request.id} kind=search keyword_id=\d+/))
    expect(Rails.logger).not_to have_received(:info).with(a_string_including("very private sentence"))
  end
end
