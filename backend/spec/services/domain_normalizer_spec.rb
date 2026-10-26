require "rails_helper"

RSpec.describe DomainNormalizer do
  describe ".call" do
    {
      "example.com" => "example.com",
      "EXAMPLE.COM" => "example.com",
      "  example.com  " => "example.com",
      "https://example.com" => "example.com",
      "http://example.com/path?q=1#frag" => "example.com",
      "https://www.example.com/" => "example.com",
      "www.example.com" => "example.com",
      "example.com." => "example.com",
      "example.com:8080/path" => "example.com",
      "blog.example.co.uk" => "blog.example.co.uk",
      "my-site.example.com" => "my-site.example.com"
    }.each do |input, expected|
      it "normalizes #{input.inspect} to #{expected.inspect}" do
        expect(described_class.call(input)).to eq(expected)
      end
    end

    it "keeps subdomains other than www" do
      expect(described_class.call("https://blog.example.com")).to eq("blog.example.com")
    end

    [ nil, "", "   " ].each do |blank|
      it "returns nil for blank input #{blank.inspect}" do
        expect(described_class.call(blank)).to be_nil
      end
    end

    {
      "localhost" => "single label",
      "192.168.0.1" => "IPv4 address",
      "http://127.0.0.1:3000" => "IPv4 address with scheme",
      "[::1]" => "IPv6 literal",
      "user:pass@example.com" => "userinfo",
      "https://user@example.com" => "userinfo with scheme",
      "ftp://example.com" => "non-http scheme",
      "javascript:alert(1)" => "javascript pseudo-URL",
      "file:///etc/passwd" => "file scheme",
      "exa mple.com" => "whitespace inside host",
      "-example.com" => "label starting with hyphen",
      "example-.com" => "label ending with hyphen",
      "exa_mple.com" => "underscore",
      "example..com" => "empty label",
      ".example.com" => "leading dot",
      "예제.com" => "non-ASCII host (not supported in the MVP)",
      "example.123" => "numeric TLD"
    }.each do |input, reason|
      it "returns nil for #{input.inspect} (#{reason})" do
        expect(described_class.call(input)).to be_nil
      end
    end

    it "returns nil when a label is longer than 63 characters" do
      expect(described_class.call("#{'a' * 64}.com")).to be_nil
    end

    it "returns nil when the host is longer than 253 characters" do
      host = ([ "a" * 60 ] * 5).join(".") + ".com"
      expect(described_class.call(host)).to be_nil
    end

    it "is idempotent" do
      once = described_class.call("https://www.Example.com/x")
      expect(described_class.call(once)).to eq(once)
    end

    it "returns nil for non-string input" do
      expect(described_class.call(123)).to be_nil
    end
  end

  describe ".match?" do
    it "matches the exact host" do
      expect(described_class.match?(host: "example.com", target: "example.com")).to be(true)
    end

    it "matches www and other subdomains of the target" do
      expect(described_class.match?(host: "www.example.com", target: "example.com")).to be(true)
      expect(described_class.match?(host: "blog.example.com", target: "example.com")).to be(true)
    end

    it "does not match a different domain that merely ends with the same text" do
      expect(described_class.match?(host: "notexample.com", target: "example.com")).to be(false)
      expect(described_class.match?(host: "example.com.evil.net", target: "example.com")).to be(false)
    end

    it "does not match the parent when the target is a subdomain" do
      expect(described_class.match?(host: "example.com", target: "blog.example.com")).to be(false)
    end

    it "normalizes both sides before comparing" do
      expect(described_class.match?(host: "https://WWW.Example.com/page", target: "EXAMPLE.com")).to be(true)
    end

    it "is false when either side is invalid or blank" do
      expect(described_class.match?(host: nil, target: "example.com")).to be(false)
      expect(described_class.match?(host: "example.com", target: "")).to be(false)
      expect(described_class.match?(host: "localhost", target: "localhost")).to be(false)
    end
  end
end
