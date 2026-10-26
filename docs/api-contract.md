# API Contract (v1)

Status after Stage 3: keyword CRUD, running searches through SerpApi, listing runs, and rank history. The intent plan and metrics endpoints are added in later stages.

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
| 429 | `search_budget_exceeded` | Daily search budget reached. `details` is `{ limit, used }`. No run is created and SerpApi is not called. |
| 429, 502, 504 | `search_failed` | The search ran and failed upstream. `details` is `{ category, run_id }`. See "Searches". |
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

A search run is one execution of a keyword's search through SerpApi. It is stored whether it succeeds or fails, so failures are visible and the last successful run is never overwritten.

Stage 3 runs a search **synchronously inside the request** (up to 5 s to connect plus 15 s to read, no retries). Stage 4 moves execution to a background job and adds caching, de-duplication, and retries. Do not call this endpoint in a loop: every call is one SerpApi request until caching exists, and `SEARCH_MAX_REQUESTS_PER_DAY` (default 5) caps the number of runs per UTC day.

| Method and path | Success | Notes |
|---|---|---|
| `POST /keywords/:keyword_id/searches` | 201 `{ data }` + `Location` | Runs the search now. Works for inactive keywords too (a manual run). The body is ignored. |
| `GET /keywords/:keyword_id/searches` | 200 `{ data: [...], meta }` | Newest first, paginated, without result bodies. |
| `GET /keywords/:keyword_id/searches/:id` | 200 `{ data }` | One run including its results ordered by position. |

Run object: `id, keyword_id, status, started_at, finished_at, upstream_latency_ms, http_status, error_category, error_message, cache_source, result_count, empty_results, request, rank, created_at` and `results` on the single-run and create responses.

- `status`: `running`, `succeeded`, or `failed`. A run is never left `running` after the request ends.
- `request` is the provenance needed to explain a ranking difference later: `provider, engine, query, country, language, location, search_id` (SerpApi's search id when it returned one).
- `rank` is `null` when the keyword has no target domain, otherwise `{ target_domain, rank, found }`. `rank` is `null` and `found` is `false` when the domain is not in the retrieved window. It is never `0`.
- `results[]`: `position, title, url, display_domain, snippet`. `display_domain` is the canonical hostname (`www.` dropped) or `null` for hosts that are not domains.
- `cache_source` is `none` for now. SerpApi documents a one-hour server-side cache but this stage does not read a cache indicator from responses, so it is not guessed. Stage 4 verifies it.

### Failure mapping

A failed run is stored with `status: failed`, an `error_category`, and the HTTP status SerpApi returned (when there was one). The create request answers with `error.code = "search_failed"` and:

| `error_category` | Cause | Response | Retried in Stage 4 |
|---|---|---|---|
| `auth` | HTTP 401 or 403, or an "api key" error in the body | 502 | No |
| `invalid_request` | HTTP 400 or 404, or a missing/invalid parameter message | 502 | No |
| `quota` | HTTP 429 with "run out of searches", or the same text in a 200 body | 429 | No |
| `rate_limit` | Any other HTTP 429 | 429 | Yes |
| `timeout` | Connect/read/write timeout, or HTTP 408 | 504 | Yes |
| `network` | DNS, connection refused/reset, TLS, or truncated response | 502 | Yes |
| `upstream` | HTTP 5xx, or `search_metadata.status` is `Error` | 502 | Yes |
| `schema` | Malformed JSON, not an object, unrecognized shape, `organic_results` not an array or without a single usable entry, or a result our validations reject | 502 | No |
| `unknown` | Anything else, including an unrecognized `error` text in a 200 body | 502 | No |

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

## Data model (Stage 2 schema)

| Table | Purpose | Key constraints |
|---|---|---|
| `keywords` | What to search | Unique index on search settings (`NULLS NOT DISTINCT`, requires PostgreSQL 15+) |
| `search_runs` | One execution: fingerprint, status, timings, error category, cache source, request metadata | FK to keyword, `fingerprint` is the settings fingerprint and is indexed (not unique: de-duplication lands in Stage 4) |
| `search_results` | Normalized organic results of a run | Unique `(search_run_id, position)`, `position >= 1`, `extra` JSON bounded to 4 KB |
| `rank_snapshots` | Target-domain rank per run | One per run, `rank` is `NULL` when not found and `>= 1` otherwise (never 0) |
| `intent_requests` | Natural-language requests and outcomes | Used from Stage 5, original text retention policy to be decided then |

`intent_requests` is not used until Stage 5.

## Known limitations

- No authentication or per-client rate limiting (local use only until Stage 8).
- Searches are synchronous and not retried. There is no result caching or concurrent-duplicate protection yet (Stage 4). The daily budget check is not atomic, so simultaneous requests can overshoot it slightly.
- The rank window is one SerpApi response (the first page of organic results). A domain ranked deeper is reported as not found.
- The text of SerpApi's hourly-rate-limit error is not documented. Any 429 that is not the "run out of searches" message is classified as `rate_limit`.
- The fixtures in `spec/fixtures/serpapi` are hand-written from the documented shapes, not recorded live responses. The only real-world checks so far are an invalid-key call (HTTP 401, matching the documented body) and the documentation itself.
- Query uniqueness is case-sensitive, so `React` and `react` are separate keywords.
- `COUNTRIES` and `LANGUAGES` are curated subsets that have not been checked against SerpApi's full supported lists. Verify in Stage 3 before extending.
