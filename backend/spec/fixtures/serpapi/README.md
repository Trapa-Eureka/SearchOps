# SerpApi fixtures

These files are **hand-written from the response shapes documented by SerpApi**
(https://serpapi.com/search-api and https://serpapi.com/api-status-and-error-codes).
They are not recordings of real responses and contain no account data or keys.

Only fields confirmed in the documentation are used: `search_metadata.id/status`,
`search_information.organic_results_state`, `organic_results[].position/title/link/displayed_link/snippet`,
and the top-level `error` string.

After a live call is approved, replace or add scrubbed recordings here (remove the
api_key, account fields, and any personal data first).
