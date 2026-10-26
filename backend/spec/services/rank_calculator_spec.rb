require "rails_helper"

RSpec.describe RankCalculator do
  def result(position, url)
    SearchProvider::Result.new(position: position, title: nil, url: url, display_domain: nil, snippet: nil, extra: {})
  end

  let(:results) do
    [
      result(1, "https://react.dev/"),
      result(2, "https://www.example.com/jobs"),
      result(3, "https://blog.example.com/post"),
      result(4, "https://notexample.com/"),
      result(5, "https://example.com.evil.net/")
    ]
  end

  it "returns the best position of the target domain" do
    expect(described_class.call(results: results, target_domain: "example.com")).to eq(2)
  end

  it "matches www and subdomains of the target" do
    expect(described_class.call(results: results, target_domain: "blog.example.com")).to eq(3)
  end

  it "does not match look-alike domains" do
    only_lookalikes = results.last(2)

    expect(described_class.call(results: only_lookalikes, target_domain: "example.com")).to be_nil
  end

  it "returns the smallest position even if results are unordered" do
    shuffled = results.shuffle(random: Random.new(1))

    expect(described_class.call(results: shuffled, target_domain: "example.com")).to eq(2)
  end

  it "returns nil, never 0, when the domain is not in the window" do
    expect(described_class.call(results: results, target_domain: "absent.org")).to be_nil
  end

  it "returns nil for an empty window" do
    expect(described_class.call(results: [], target_domain: "example.com")).to be_nil
  end

  it "returns nil when there is no target domain" do
    expect(described_class.call(results: results, target_domain: nil)).to be_nil
    expect(described_class.call(results: results, target_domain: "")).to be_nil
  end

  it "ignores results whose URL has userinfo that would disguise the host" do
    tricky = [ result(1, "https://example.com@evil.net/") ]

    expect(described_class.call(results: tricky, target_domain: "example.com")).to be_nil
  end

  it "works with persisted SearchResult records" do
    run = create(:search_run)
    create(:search_result, search_run: run, position: 7, url: "https://www.example.com/x")

    expect(described_class.call(results: run.search_results, target_domain: "example.com")).to eq(7)
  end
end
