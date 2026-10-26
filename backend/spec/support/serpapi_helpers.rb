module SerpapiHelpers
  SERPAPI_URL = "https://serpapi.com/search".freeze

  def serpapi_fixture(name)
    File.read(Rails.root.join("spec/fixtures/serpapi/#{name}.json"))
  end

  def stub_serpapi(body: nil, fixture: nil, status: 200, headers: { "Content-Type" => "application/json" })
    body ||= serpapi_fixture(fixture)
    stub_request(:get, SERPAPI_URL).with(query: hash_including({})).to_return(status: status, body: body, headers: headers)
  end
end

RSpec.configure do |config|
  config.include SerpapiHelpers
end
