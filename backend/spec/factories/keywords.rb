FactoryBot.define do
  factory :keyword do
    sequence(:query) { |n| "react developer #{n}" }
    engine { "google" }
    country { "us" }
    language { "en" }
    location { nil }
    target_domain { nil }
    active { true }
    schedule { "manual" }
  end

  factory :search_run do
    keyword
    fingerprint { SecureRandom.hex(16) }
    status { "succeeded" }
    cache_source { "none" }
  end

  factory :search_result do
    search_run
    sequence(:position) { |n| n }
    title { "Example title" }
    url { "https://example.com/page" }
    display_domain { "example.com" }
    snippet { "Example snippet" }
  end

  factory :rank_snapshot do
    keyword
    search_run { association :search_run, keyword: keyword }
    target_domain { "example.com" }
    rank { 3 }
    captured_at { Time.current }
  end

  factory :intent_request do
    original_text { "find remote react jobs in the philippines" }
    outcome { "planned" }
  end
end
