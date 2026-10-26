# API Contract (v1)

Status after Stage 4: keyword CRUD, asynchronous searches through SerpApi (with caching, de-duplication, retries, and scheduled checks), run listing, rank history, and a metrics summary. Stage 5 adds optional natural-language planning (`/intent/plan`). Stage 6 adds two read-only endpoints for the dashboard (`/options`, `/searches`), a time series in the metrics, and an `activity` summary on keywords.

Base path: `/api/v1`. Format: JSON. **No authentication yet**: the API is for local development only and must not be exposed publicly until Stage 8 adds authentication, CORS, and HTTPS.

## Conventions

Success responses wrap the payload:

```json
{ "data": { }, "meta": { } }
```

Errors share one shape. Internal exception messages are never returned.

```json
{ "error": { "code": "validation_failed", "message": "Validation failed", "details": { "query": ["can't be blank"] } } }
```

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `bad_request` | Missing `keyword` payload or malformed JSON |
| 404 | `not_found` | Unknown id (including non-numeric ids, or a run that belongs to another keyword) |
| 409 | `conflict` | Database unique index hit (concurrent duplicate create) |
| 422 | `validation_failed` | Validation errors, listed per field in `details` (`base` for record-level errors) |
| 429 | `search_budget_exceeded` | Daily search budget reached. `details` is `{ limit, used }`. No run is created and nothing is queued. |
| 503 | `search_provider_not_configured` | `SERPAPI_API_KEY` is missing or still the placeholder. Nothing was sent and no run was created. |

Pagination (list endpoints): `?page=1&per_page=25`. `per_page` defaults to 25 and is capped at 100. Missing, non-numeric, zero, or negative values fall back to the defaults. A page beyond the last returns an empty `data` array. `meta` is `{ page, per_page, total_count, total_pages }`.

## Keywords

A keyword is a search setting to track: query, engine, country, language, optional location, and an optional target domain whose rank is tracked.

Fields:

| Field | Type | Rules |
|---|---|---|
| `query` | string, required | Whitespace is squished. Max 200 characters. No control characters. Case is preserved and matters for uniqueness. |
| `engine` | string | Default `google`. Only `google` is allowed for now. |
| `country` | string, required | Lowercased. One of the curated list in `Keyword::COUNTRIES` (maps to SerpApi `gl`). |
| `language` | string, required | Lowercased. One of `Keyword::LANGUAGES` (maps to SerpApi `hl`). |
| `location` | string or null | Free text, max 100 characters, blank becomes `null`. |
| `target_domain` | string or null | Normalized to a bare lowercase hostname (see below). Blank becomes `null`. |
| `active` | boolean | Default `true`. Only active keywords are scheduled (Stage 4). |
| `schedule` | string | `manual` (default), `daily`, or `weekly`. |

Uniqueness: the combination of `query`, `engine`, `country`, `language`, `location`, and `target_domain` must be unique (a missing location or target domain counts as equal). Enforced by validation and by a database unique index.

Limit: at most `SEARCH_MAX_KEYWORDS` keywords (default 50), so scheduled checks cannot grow API usage without bound.

`target_domain` normalization (`DomainNormalizer`): `https://www.Example.com/path?x=1` becomes `example.com`. A leading `www.` is dropped; other subdomains are kept. Rejected: single-label hosts (`localhost`), IP addresses, ports are stripped, userinfo, non-HTTP(S) schemes, non-ASCII hosts, and malformed labels. Matching against result hosts (used from Stage 3): a result matches when its host equals the target or is a subdomain of it, so `blog.example.com` matches `example.com` but `notexample.com` does not.

Response object (`KeywordSerializer`): `id, query, engine, country, language, location, target_domain, active, schedule, created_at, updated_at`. `id`, `created_at`, and `updated_at` cannot be set by clients.

### Activity summary

Every keyword in `GET /keywords` and `GET /keywords/:id` (and in create and update responses) carries `activity`, so a list can show how a keyword is doing without one request per row. It is computed for a whole page in a fixed number of queries.

```json
"activity": {
  "recent_runs": [ { "id": 41, "status": "succeeded", "cache_hit": false, "error_category": null, "latency_ms": 912, "retried": false, "created_at": "..." } ],
  "latency_ms": { "samples": 18, "p95": 4210, "max": 15000 },
  "rank": { "rank": 3, "found": true, "captured_at": "...", "target_domain": "react.dev", "comparison": { "status": "improved", "delta": 2, "previous_rank": 5 } }
}
```

- `recent_runs`: the newest 20 runs, **oldest first**, including cache hits and runs that are still queued or running. It contains no search terms, results, or error text.
- `latency_ms`: percentile over the runs in `recent_runs` that called SerpApi and recorded a latency (cache hits are excluded). It describes those runs only, not all time.
- `rank`: the newest rank snapshot compared with the one before it, exactly as in [Rank history](#rank-history): smaller is better, `null` rank means not found in the retrieved window (never 0), and snapshots from different search settings are `not_comparable`. `null` when the keyword has no snapshot (no target domain, or never searched).

### Endpoints

| Method and path | Success | Notes |
|---|---|---|
| `GET /keywords` | 200 `{ data: [...], meta }` | Newest first. Optional filter `?active=true` or `false`. |
| `POST /keywords` | 201 `{ data }` + `Location` header | Body `{ "keyword": { ... } }`. The attributes may also be sent without the `keyword` wrapper. |
| `GET /keywords/:id` | 200 `{ data }` | |
| `PATCH /keywords/:id` | 200 `{ data }` | Partial update. Send `null` or `""` to clear `location` or `target_domain`. |
| `DELETE /keywords/:id` | 204 | Also deletes the keyword's runs, results, and rank snapshots. |

Example:

```bash
curl -X POST localhost:3000/api/v1/keywords \
  -H 'Content-Type: application/json' \
  -d '{"keyword":{"query":"senior react developer","country":"ph","language":"en","location":"Manila","target_domain":"https://www.example.com/jobs"}}'
```

```json
{"data":{"id":1,"query":"senior react developer","engine":"google","country":"ph","language":"en","location":"Manila","target_domain":"example.com","active":true,"schedule":"manual","created_at":"2026-10-26T00:54:37.567Z","updated_at":"2026-10-26T00:54:37.567Z"}}
```

## Searches

A **run** is one search request for a keyword. Every request leaves a run, whether it was queued, answered from the cache, succeeded, or failed, so failures are visible and the last successful run is never overwritten.

The request does **not** call SerpApi. It queues the work and returns immediately; a background worker (Solid Queue, stored in the same PostgreSQL database) performs the call. Poll the run to see the result.

| Method and path | Success | Notes |
|---|---|---|
| `POST /keywords/:keyword_id/searches` | 200 or 202 `{ data, meta: { outcome } }` + `Location` | Works for inactive keywords too (a manual run). Optional `?refresh=true`. |
| `GET /keywords/:keyword_id/searches` | 200 `{ data: [...], meta }` | Newest first, paginated, without result bodies. |
| `GET /keywords/:keyword_id/searches/:id` | 200 `{ data }` | One run including its results ordered by position. |

`meta.outcome` of the POST:

| outcome | HTTP | Meaning |
|---|---|---|
| `enqueued` | 202 | A new run was queued (`status: queued`). Poll `GET .../searches/:id`. |
| `deduplicated` | 202 | An identical run (same keyword and search settings) is already queued or running; that run is returned and nothing new is created. |
| `cache_hit` | 200 | A successful run for the same settings finished within the cache TTL, so no SerpApi call is made. The response is a new run with `cache_source: "app"` and the results included. |

Errors of the POST itself: 404 unknown keyword, 429 `search_budget_exceeded`, 503 `search_provider_not_configured` (the key is missing or still the placeholder; nothing is queued).

### Run object

`id, keyword_id, status, triggered_by, started_at, finished_at, attempts, upstream_calls, upstream_latency_ms, http_status, error_category, error_message, attempt_log, cache_source, cache, result_count, empty_results, request, rank, created_at`, plus `results` on the single-run endpoint and for succeeded runs returned by the POST.

- `status`: `queued` (waiting for a worker, or waiting for a retry), `running`, `succeeded`, or `failed`.
- `triggered_by`: `manual` (the API) or `scheduled` (the recurring job).
- `attempts` is how many times a worker tried; `upstream_calls` is how many requests were really sent to SerpApi. A cache hit has both at 0. `upstream_calls` is what the daily budget counts.
- `upstream_latency_ms` is the duration of the last attempt.
- `attempt_log` lists the earlier failed attempts of a retried run (`attempt, category, http_status, message`, at most 5).
- `cache` is `{ hit, source_run_id, age_seconds }`. For a hit, `results` and `rank` are those of the source run.
- `cache_source` is `app` for a local cache hit and `none` otherwise. SerpApi has its own server-side cache (an identical request within one hour is free on their side), but SerpApi documents no response field that says a result came from it, so it cannot be observed and `serpapi` is never reported.
- `request` is the provenance needed to explain a ranking difference later: `provider, engine, query, country, language, location, search_id`.
- `rank` is `null` when the keyword has no target domain, otherwise `{ target_domain, rank, found }`. `rank` is `null` and `found` is `false` when the domain is not in the retrieved window. It is never `0`.
- `results[]`: `position, title, url, display_domain, snippet`. `display_domain` is the canonical hostname (`www.` dropped) or `null` for hosts that are not domains.

### Lifecycle, de-duplication, and idempotency

```text
queued --(worker claims)--> running --> succeeded
   ^                           |
   |        retryable error    +--> failed   (final: no retries left, or not retryable)
   +---------------------------+
```

- A run is claimed with an atomic conditional update, so if the same job is delivered twice only one worker calls SerpApi.
- A database partial unique index allows at most one `queued` or `running` run per keyword and search settings. Concurrent requests, or a scheduler that fires twice, therefore cannot start duplicate upstream calls.
- A recurring cleanup job closes runs that are `running` for more than 10 minutes or `queued` for more than 30 minutes as `failed` with category `abandoned` (a crashed worker or lost job), so a stuck run can never block a keyword forever.
- Search settings are identified by a fingerprint (SHA-256 of engine, query, country, language, and location; query and location are case-folded). The target domain is not part of it.

### Cache

A recent successful run is the cache entry: the newest `succeeded` run for the same keyword and fingerprint whose `finished_at` is within `SEARCH_CACHE_TTL_SECONDS` (default 3600, `0` disables the cache, an unreadable value falls back to the default). It is used only if its rank snapshot matches the keyword's current target domain. Cache entries are not shared between keywords. A hit creates its own run (so hits are counted exactly), no new rank snapshot, and costs no budget. `?refresh=true` skips the cache; it is still de-duplicated and counted against the budget.

### Retries

Only transient failures are retried: `network`, `timeout`, `rate_limit`, and `upstream`. A run is tried at most 3 times. The wait before a retry is a capped exponential backoff with jitter: the ceiling is 2 s, 4 s, 8 s, ... up to 60 s, and the actual delay is random between half of the ceiling and the full ceiling. If SerpApi sends a `Retry-After` header (not mentioned in its docs, so only honored when present, in seconds), that value is used instead, capped at 300 s. `auth`, `quota`, `invalid_request`, `schema`, and `unknown` failures are final on the first attempt. When retries are exhausted the run is `failed` with the last error; the last successful run and its snapshot stay untouched.

### Daily budget and concurrency

`SEARCH_MAX_REQUESTS_PER_DAY` (default 5) caps real upstream calls per UTC day, retries included. Each queued run that has not been tried yet reserves one call, so a burst of requests cannot overshoot the cap. The check happens when the request is queued (429 and no run) and again before every attempt (the run fails with category `budget`). An unreadable value becomes 0, which blocks all searches. This is only a local guard: read the real plan and usage with `bin/rails searchops:serpapi_quota`, which uses SerpApi's free Account API and prints only quota fields (never the key or the e-mail).

`SEARCH_MAX_CONCURRENCY` (default 2) limits how many searches talk to SerpApi at the same time, across all workers and processes (Solid Queue concurrency control).

### Scheduled checks

`ScheduleSearchesJob` runs every 10 minutes (`config/recurring.yml`) and queues a search, with `triggered_by: scheduled`, for every active keyword whose `schedule` is `daily` (24 h) or `weekly` (7 days) and that has had no upstream run within that interval. A failed attempt counts as an attempt, and a cache hit does not. It never involves Laya. If the key is not configured it does nothing; if the budget is spent it stops for the day without creating failed runs.

### Failure categories

A failed run has `status: failed` and an `error_category`:

| `error_category` | Cause | Retried |
|---|---|---|
| `auth` | HTTP 401 or 403, an "api key" error in the body, or a missing key when the job runs | No |
| `invalid_request` | HTTP 400 or 404, or a missing/invalid parameter message | No |
| `quota` | HTTP 429 with "run out of searches", or the same text in a 200 body | No |
| `rate_limit` | Any other HTTP 429 | Yes |
| `timeout` | Connect/read/write timeout, or HTTP 408 | Yes |
| `network` | DNS, connection refused/reset, TLS, or truncated response | Yes |
| `upstream` | HTTP 5xx, or `search_metadata.status` is `Error` | Yes |
| `schema` | Malformed JSON, not an object, unrecognized shape, `organic_results` not an array or without a single usable entry, or a result our validations reject | No |
| `unknown` | Anything else, including an unrecognized `error` text in a 200 body | No |
| `budget` | The daily budget was spent before an attempt could be made | No |
| `abandoned` | A worker never finished the run and the cleanup job closed it | No |

### Freshness

Keyword responses include a `freshness` object so the UI can mark old data instead of silently showing it:

```json
{ "state": "stale", "reason": "last_attempt_failed", "last_success_at": "2026-10-26T01:10:00.000Z",
  "last_attempt_status": "failed", "last_attempt_at": "2026-10-26T05:10:00.000Z" }
```

| state | meaning |
|---|---|
| `no_data` | No successful search yet. |
| `fresh` | Last attempt succeeded and, for scheduled keywords, the last success is recent enough. |
| `stale` | `reason: last_attempt_failed`: the newest finished attempt failed, so the shown rank is older than the latest attempt. Or `reason: overdue`: a scheduled keyword's last success is older than 1.5 intervals (36 h for daily, 10.5 days for weekly). `manual` keywords are never overdue. |

Cache hits and unfinished runs are ignored. The same object appears in `meta.freshness` of the rank history.

### Empty results are not failures

SerpApi reports an empty result set as HTTP 200 with `search_metadata.status` `Success` and a top-level `error` of "Google hasn't returned any results for this query." That is stored as a **succeeded** run with `result_count: 0` and `empty_results: true`, and a rank snapshot with a `null` rank. A successful response with no `organic_results` is treated the same way.

Because an empty SERP can also be a transient upstream problem, `empty_results` is kept on the run so a consumer can tell "the domain really dropped out" apart from "the whole result page was empty".

### Result normalization

Only documented fields are read: `organic_results[].position, title, link, displayed_link, snippet`, plus `search_metadata.id/status`. Entries without a usable `http(s)` link are skipped (counted in the run's `skipped_results` metadata, not guessed). A missing, duplicate, or invalid `position` is replaced with the next free one. Titles, snippets, and displayed links are truncated to the model limits rather than failing the run.

### Secrets

The API key is read from the environment on the server, sent only to the fixed `https://serpapi.com/search` endpoint, redacted from stored error messages, and never returned or logged. The search text is stored with the run (provenance) but is left out of log lines.

## Rank history

`GET /keywords/:keyword_id/rank_history` returns the target domain's rank over time, newest first, paginated.

```json
{
  "data": [
    { "id": 12, "search_run_id": 31, "target_domain": "example.com", "rank": 3, "found": true,
      "captured_at": "2026-10-26T01:10:00.000Z",
      "comparison": { "status": "improved", "delta": 2, "previous_rank": 5 } }
  ],
  "meta": { "page": 1, "per_page": 25, "total_count": 1, "total_pages": 1, "target_domain": "example.com",
            "ordering": "newest_first", "rank_semantics": "lower_is_better",
            "null_rank_meaning": "not_found_in_retrieved_window" }
}
```

- A **smaller rank is a better position**. `delta = previous_rank - rank`, so a positive `delta` means the domain moved up.
- `rank: null` with `found: false` means "not found in the retrieved window" (what one SerpApi request returned), not "ranked last". It is not a global ranking: it describes this query, country, language, and location at `captured_at`.
- Each entry is compared with the snapshot just before it (also across page boundaries). `comparison.status`:

| status | meaning |
|---|---|
| `improved` / `declined` / `unchanged` | Both found. `delta` is positive / negative / 0. |
| `entered` | Not found before, found now. |
| `dropped` | Found before, not found now (how far it fell is unknown). |
| `not_found` | Not found in either snapshot. |
| `baseline` | The first snapshot, nothing to compare with. |
| `not_comparable` | The two runs have different search settings (fingerprint) or different target domains, so no change is claimed. |

The settings fingerprint (`SearchFingerprint`) is a SHA-256 of engine, query, country, language, and location, with the query and location case-folded. The target domain is not part of it; it is compared separately.

## Natural-language planning (optional)

Turns a sentence into a **proposed plan**; nothing runs until the client confirms. It is optional in every sense: with `LAYA_ENABLED=false` (the default), or when Laya is down, these endpoints still answer with a structured-input fallback, and keywords, searches, scheduled checks, rank history, and metrics are unaffected. How the classifier is called and how well it works: [laya-contract.md](laya-contract.md) and [intent-eval.md](intent-eval.md).

| Method and path | Success | Notes |
|---|---|---|
| `POST /intent/plan` | 201 `{ data }` + `Location` | Body `{ "text": "..." }`. Always 201 when the text is acceptable, whatever `data.status` says. |
| `GET /intent/plan/:id` | 200 `{ data }` | Read a stored plan again. |
| `POST /intent/plan/:id/confirm` | 200 `{ data }` | Optional body `{ "plan": { ...edits... } }`. Carries the plan out through the normal keyword and search path. |

`text` must be a string of 1 to 500 characters after whitespace is squished, without control characters; otherwise 422 `invalid_text` with `details: { text: "text_required" | "text_must_be_a_string" | "text_too_long" | "text_has_control_characters" }` and nothing is stored. `POST /intent/plan` is limited to 30 requests per minute per IP (429 `rate_limited`; the counter is per process).

### How a sentence becomes a plan

1. Rules extract what Laya cannot: country (and its main language), a target domain, and quoted keyword candidates (`Intent::Extractor`). Country and domain are never guessed: two different values are reported as ambiguous.
2. The keyword and domain are masked in the sentence (`KEYWORD`, `DOMAIN`) and Laya classifies the rest into one of `organic_rank_tracking`, `job_search`, `search_history`, `unsupported`, with a probability for each.
3. Below `LAYA_MIN_CONFIDENCE` (default 0.7) nothing is proposed, only a clarification with the two likeliest intents. `unsupported` above the threshold is reported as out of scope.
4. Otherwise a plan is built and checked by a strict validator (`Intent::PlanValidator`): the field set is closed, unknown fields are rejected, codes come from allow-lists, domains must be safe hostnames, flags must be real booleans. There is no field that could express a delete, an export, an engine override, or a repeat count.
5. `compare_previous` and `only_new` come from word lists (English, Korean, Japanese, and the local wording of the evaluation languages), not from Laya.

### The response

`data`: `id, status, reason, next_step, plan, requires_confirmation, missing, errors, fields, candidates, keyword_candidates, query_suggestions, history, notes, classifier, structured_input, execution, created_at, confirmed_at`. The original sentence is **not** returned.

| `status` | `reason` | Meaning | `next_step` |
|---|---|---|---|
| `ready` | | A complete, valid plan awaiting confirmation. | `confirm` |
| `needs_clarification` | `low_confidence` | The classifier was not sure. `plan` is `null`; `candidates` lists the two likeliest intents. | `rephrase_or_use_structured_input` |
| `needs_clarification` | `missing_fields` | Understood, but `missing` fields could not be found (`query`, `country`, `language`, `target_domain`). `query_suggestions` may help. | `complete_fields` (send them in `plan` when confirming) |
| `needs_clarification` | `ambiguous_keyword` / `keyword_not_found` | A history request matched several tracked keywords (`keyword_candidates`) or none. | `complete_fields` |
| `needs_clarification` | `invalid_fields` | An extracted value failed validation (`errors`). | `complete_fields` |
| `unsupported` | `out_of_scope` | Understood as something this app does not do. | `none` |
| `unsupported` | `engine_not_available` | A `job_search` plan: understood and kept in `plan` (engine `google_jobs`), but that engine is not implemented, so it cannot be confirmed. | `none` |
| `unavailable` | `laya_disabled` or `classifier_<timeout, unavailable, busy, auth, bad_request, server_error, invalid_response>` | Laya is off or failed; nothing was understood. `structured_input.prefill` still holds what the rules found. | `use_structured_input` |
| `executed` | | Confirmed and carried out; see `execution`. | `none` |

- `plan` keys: `intent, engine, query, country, language, location, target_domain, keyword_id, compare_previous, only_new` (only those that apply). `engine` is derived from the intent.
- `fields` says where each value came from: `{ source: "laya" | "rule" | "missing" | "default", evidence, confidence }`. For example the intent is `laya` with its probability, the country is `rule` with the matched word, and a flag is `rule` when a cue matched.
- `classifier`: `{ name, enabled, version, intent, confidence, probabilities, min_confidence, latency_ms }`. `version` is `laya:<checkpoint>@<LAYA_VERSION_LABEL>`.
- `history` (when `compare_previous` is on): `{ keyword_id, snapshots }`; `notes` contains `baseline_only` when no earlier snapshot exists, so only a baseline can be created now. Nothing is fabricated for a missing last week.
- `structured_input`: `{ endpoint: "/api/v1/keywords", fields, prefill }`, present for every status that is not `ready`, `executed`, or `unsupported`: the way to do the same thing without the classifier.
- `requires_confirmation` is true for `organic_rank_tracking` (it can start a search). `search_history` is read-only.

### Confirming

`POST /intent/plan/:id/confirm` first checks the SerpApi key is configured for rank checks (503 `search_provider_not_configured`), then:

- merges the optional `plan` edits (`query, country, language, location, target_domain, compare_previous, only_new` and `keyword_id`) into the stored plan and **validates the whole plan again**. The intent cannot be changed. Unknown fields, bad values, and missing fields give 422 `invalid_plan` with `details: { errors, missing }`.
- `organic_rank_tracking`: finds or creates the keyword (same limits and uniqueness as the keyword API) and calls the normal search path, so caching, de-duplication, the daily budget, and retries all apply. `execution` is `{ kind: "search", keyword_id, keyword_created, run_id, search_outcome }` where `search_outcome` is `enqueued`, `deduplicated`, or `cache_hit`. Poll the run as usual.
- `search_history`: `execution` is `{ kind: "history", keyword_id }` (`null` means all keywords). No search is made.
- A request with nothing to confirm (low confidence, out of scope, unavailable) gives 422 `not_confirmable` with `details.reason` `no_plan_to_confirm`; a job search gives `engine_not_available`.
- Idempotent: confirming again returns the first result without searching again. If the daily budget is spent (429 `search_budget_exceeded`) the plan stays unconfirmed and can be confirmed later. The classifier is never called when confirming.

### Safety properties (each covered by specs)

- Laya's answer is a label and numbers, validated against the known labels; anything else counts as an outage.
- A wrong classification can end at most as a read-only history view, or a rank check the user confirmed, counted against the budget. Prompt-injection sentences were tested with a classifier forced to answer with full confidence for every intent.
- The user's keyword and domain are not sent to Laya. The Laya address is an operator setting and never comes from a request.
- The sentence is stored only in `intent_requests.original_text`, never logged (log lines carry ids, outcome, intent, confidence, reason, and timings), never returned, and deleted after `INTENT_RETENTION_DAYS` (default 30) by `PurgeIntentRequestsJob`. Keywords and runs created by a confirmed plan do not reference the sentence and stay.

## Options (for clients)

`GET /api/v1/options` returns the allowed values and limits, read from the models that enforce them, so a client never copies them. Read-only, no parameters.

```json
{ "data": {
    "engines": ["google"], "countries": ["us", "ph", "..."], "languages": ["en", "ko", "..."], "schedules": ["manual", "daily", "weekly"],
    "limits": { "query_max_length": 200, "location_max_length": 100, "max_keywords": 50, "intent_text_max_length": 500, "max_per_page": 100 },
    "features": { "intent_planning": false }
} }
```

`features.intent_planning` is `true` only when `LAYA_ENABLED` is on. It says nothing about whether the Laya server is reachable; that is only discovered when a sentence is classified.

## Recent runs across keywords

`GET /api/v1/searches` lists runs of every keyword, newest first, paginated. Each item is the run object (see [Run object](#run-object)) without result rows, plus `keyword: { id, query, country, language, target_domain }`. It is the data behind the dashboard's request timeline. A single run with its results stays under `GET /keywords/:id/searches/:run_id`.

| Query | Effect |
|---|---|
| `status` | `queued`, `running`, `succeeded`, or `failed`. Any other value is ignored (not an error). |
| `error_category` | One of the failure categories. Any other value is ignored. |
| `keyword_id` | Digits only; anything else is ignored. |

`meta.counts` is `{ all, queued, running, succeeded, failed }`: how many runs each status has under the `keyword_id` and `error_category` filters, **before** the `status` filter, so filter tabs can show their totals and the numbers do not change when a tab is chosen.

## Metrics

`GET /api/v1/metrics/summary?window=24h` (`1h`, `24h` default, `7d`, or `30d`; anything else is 400) returns operational numbers computed from the runs table. It contains counts and timings only, never search terms, error text, or credentials.

| Section | Fields |
|---|---|
| `window` | `name, from, to` |
| `series` | `bucket_seconds` and `buckets`: one entry per time slice of the window, oldest first, each `{ at, succeeded, cache_hit, failed, active }`. Slices without requests are included with zeros. Slice width: 5 min for `1h` (12 slices), 1 h for `24h` (24), 12 h for `7d` (14), 1 day for `30d` (30). A request counts in the slice of its creation time and in exactly one outcome: `failed`; `active` (queued or running); `cache_hit` (answered from the local cache); otherwise `succeeded` (answered by SerpApi). The slices add up to `requests.total`. |
| `requests` | `total`, `by_status` (queued, running, succeeded, failed), `by_trigger` (manual, scheduled). Every search request is a run, cache hits included. |
| `upstream` | `calls` (requests sent to SerpApi), `retries`, `runs_succeeded`, `runs_failed`, `success_rate` (`null` when nothing finished), `latency_ms: { samples, p50, p95, max }` (last attempt of each run) |
| `cache` | `hits`, `misses` (requests that really went upstream), `hit_rate` (`null` without data), `ttl_seconds`. SerpApi's own cache is not observable and not included. |
| `errors` | Failed runs by `error_category` |
| `budget` | `daily_limit, used_today, remaining_today` |
| `keywords` | `total, active, scheduled, stale, no_data` |
| `intent` | `enabled`, `requests`, `by_outcome`, `fallbacks` (by reason), `laya_latency_ms: { samples, p50, p95, max }`. Counts and timings only, never sentences. |
| `queue` | `queued, running, oldest_queued_age_seconds, workers_alive`. `workers_alive` is the number of Solid Queue workers with a recent heartbeat; `0` while runs stay queued means no worker is processing. |

Structured log lines (no search terms or credentials) are written for each step: `search_enqueued`, `search_deduplicated`, `search_cache_hit`, `search_attempt` (outcome, error category, HTTP status, latency), `search_retry` (delay), `search_failed`, `schedule_tick`, `schedule_budget_exhausted`, `reap_stuck_runs`.

## Data model (Stage 4 schema)

| Table | Purpose | Key constraints |
|---|---|---|
| `keywords` | What to search | Unique index on search settings (`NULLS NOT DISTINCT`, requires PostgreSQL 15+) |
| `search_runs` | One search request: fingerprint, status, trigger, attempts, upstream calls, timings, error category, cache source and source run, request metadata | FK to keyword. Partial unique index on `(keyword_id, fingerprint)` for `queued`/`running` rows. Counters are non-negative (CHECK). |
| `search_results` | Normalized organic results of a run | Unique `(search_run_id, position)`, `position >= 1`, `extra` JSON bounded to 4 KB |
| `rank_snapshots` | Target-domain rank per run | One per run, `rank` is `NULL` when not found and `>= 1` otherwise (never 0) |
| `intent_requests` | Natural-language requests: sentence (purged after the retention period), plan, outcome, analysis, execution | Outcome is one of planned, needs_clarification, unsupported, unavailable, executed |
| `solid_queue_*` | Job storage of Solid Queue (Active Job backend) | Created by a migration in the primary database; no Redis needed |



## Known limitations

- The dashboard is a client of this API only; it holds no data and no credential of its own. Without authentication it must stay local (Stage 8).
- No authentication, and rate limiting only on `POST /intent/plan` (per process, per IP). Local use only until Stage 8.
- Natural-language planning: intent accuracy is 74 to 77% on small, author-labeled sets (Korean 62 to 64%), and most sentences end in a clarification, not a ready plan. `job_search` cannot be confirmed because its engine is not implemented. See [intent-eval.md](intent-eval.md).
- The daily budget check is not atomic, so simultaneous requests can overshoot it slightly. Queued runs reserve a call, which narrows but does not remove the gap.
- The cache is per keyword. Two keywords with identical search settings (different target domains only) do not share results.
- Retried runs report the latency of the last attempt only.
- The rank window is one SerpApi response (the first page of organic results). A domain ranked deeper is reported as not found.
- The text of SerpApi's hourly-rate-limit error is not documented. Any 429 that is not the "run out of searches" message is classified as `rate_limit`. `Retry-After` is not documented either and is honored only when present.
- Pagination (`start`) is documented but whether each page counts as a separate search is not, so ranks beyond the first response are not fetched.
- The fixtures in `spec/fixtures/serpapi` are hand-written from the documented shapes, not recorded live responses. The only real-world checks so far are an invalid-key call (HTTP 401, matching the documented body) and the documentation itself.
- Query uniqueness is case-sensitive, so `React` and `react` are separate keywords.
- `COUNTRIES` and `LANGUAGES` are curated subsets that have not been checked against SerpApi's full supported lists. Verify in Stage 3 before extending.
