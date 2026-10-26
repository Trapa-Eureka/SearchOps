namespace :searchops do
  desc "Show the SerpApi plan and usage (Account API: free, not counted toward the search quota)"
  task serpapi_quota: :environment do
    abort "SERPAPI_API_KEY is not configured (set it in backend/.env)" unless Providers::SerpApiSearchProvider.configured?

    Providers::SerpApiSearchProvider.from_env.account.each { |name, value| puts "#{name}: #{value}" }
  rescue SearchProvider::Error => error
    abort "SerpApi account lookup failed (#{error.category}): #{error.message}"
  end
end
