require "rails_helper"
require "rake"

RSpec.describe "rake searchops:serpapi_quota" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("searchops:serpapi_quota")
  end

  let(:task) { Rake::Task["searchops:serpapi_quota"] }

  before { task.reenable }

  it "prints the quota fields and nothing secret", env: { "SERPAPI_API_KEY" => "rake-spec-key-12345" } do
    stub_request(:get, /account.json/).to_return(
      status: 200,
      body: { api_key: "rake-spec-key-12345", account_email: "me@example.com", plan_name: "Free Plan",
              searches_per_month: 100, total_searches_left: 77, this_month_usage: 23 }.to_json
    )

    output = capture_stdout { task.invoke }

    expect(output).to include("plan_name: Free Plan", "total_searches_left: 77", "this_month_usage: 23")
    expect(output).not_to include("rake-spec-key-12345")
    expect(output).not_to include("me@example.com")
  end

  it "aborts with a clear message when no key is configured", env: { "SERPAPI_API_KEY" => "replace_me" } do
    expect { capture_stdout { task.invoke } }.to raise_error(SystemExit)
    expect(a_request(:any, /serpapi.com/)).not_to have_been_made
  end

  it "aborts with the error category when SerpApi rejects the key", env: { "SERPAPI_API_KEY" => "bad-key-1234567" } do
    stub_request(:get, /account.json/).to_return(status: 401, body: serpapi_fixture("invalid_api_key"))

    expect { capture_stdout { task.invoke } }.to raise_error(SystemExit)
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
