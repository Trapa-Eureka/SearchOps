# API Contract (v1)

Status after Stage 2: keyword CRUD only. All other endpoints in `CLAUDE.md` (searches, rank history, intent plan, metrics) are added in later stages.

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
| 404 | `not_found` | Unknown id (including non-numeric ids) |
| 409 | `conflict` | Database unique index hit (concurrent duplicate create) |
| 422 | `validation_failed` | Validation errors, listed per field in `details` (`base` for record-level errors) |

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

## Data model (Stage 2 schema)

| Table | Purpose | Key constraints |
|---|---|---|
| `keywords` | What to search | Unique index on search settings (`NULLS NOT DISTINCT`, requires PostgreSQL 15+) |
| `search_runs` | One execution: fingerprint, status, timings, error category, cache source, request metadata | FK to keyword, `fingerprint` indexed (not unique yet, idempotency lands in Stage 4) |
| `search_results` | Normalized organic results of a run | Unique `(search_run_id, position)`, `position >= 1`, `extra` JSON bounded to 4 KB |
| `rank_snapshots` | Target-domain rank per run | One per run, `rank` is `NULL` when not found and `>= 1` otherwise (never 0) |
| `intent_requests` | Natural-language requests and outcomes | Used from Stage 5, original text retention policy to be decided then |

Only `keywords` is exposed through the API in Stage 2. The other tables have models, validations, and tests, but are filled starting in Stage 3.

## Known limitations

- No authentication or per-client rate limiting (local use only until Stage 8).
- Query uniqueness is case-sensitive, so `React` and `react` are separate keywords.
- `COUNTRIES` and `LANGUAGES` are curated subsets that have not been checked against SerpApi's full supported lists. Verify in Stage 3 before extending.
