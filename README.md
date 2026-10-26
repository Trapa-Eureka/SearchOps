# SearchOps — Search Intelligence & API Monitoring

**English** · [Korean](README.ko.md)

> **Status: Stage 4 (jobs, cache, retries, metrics) is complete: searches run in a background worker with a local cache, de-duplication, a daily budget, capped retries, scheduled checks, stale-data marking, and a metrics summary. Verified with 427 specs, plus a live run of the real job queue against a deliberately invalid key; a successful live search was verified in Stage 3, but the retry path has only been exercised with mocked HTTP.**
> The checklist below defines what must be answerable with "yes" when the project is finished. An item is marked `[x]` only once it is implemented.

SearchOps runs keyword searches through [SerpApi](https://serpapi.com), stores the results as snapshots, tracks **rank changes for a target domain**, and monitors **latency, errors, cache hits, and usage** of the upstream API. The goal is to learn Ruby/Rails by building a service with production-minded concerns: reliability, observability, and testing.

Natural-language requests (for example, "Find remote React jobs in the Philippines and show only new results since last week") can optionally go through [Laya](https://github.com/NandhaKishorM/laya), which **only classifies intent** and turns it into a validated `SearchPlan`. Rails always executes the plan. **The core search flow must work 100% without Laya.**

> This is a personal learning project. It is not affiliated with or endorsed by SerpApi or Laya.

## Principles

1. **Deterministic path first.** Structured searches, scheduled checks, and history reads never touch Laya. Everything works with `LAYA_ENABLED=false`.
2. **Laya output is untrusted input.** It is a proposal only. Rails re-validates intent, engine, locale, query, and limits on the server.
3. **No claims without evidence.** Only fields present in stored snapshots and SerpApi responses are shown. If no earlier data exists, the app says only a baseline snapshot can be created now.
4. **Secrets stay on the server.** API keys live in environment variables only, never in git, the frontend bundle, logs, fixtures, or this README.
5. **Verified facts only.** SerpApi response fields and Laya interfaces are used only after checking official docs or real source. Anything unverified is marked as an assumption and tested with mocks.

## Architecture (target)

```text
Next.js + TypeScript + Tailwind dashboard
      |
      |-- structured keyword / scheduled request ---> Rails REST API
      |
      `-- natural-language request --> Rails endpoint --> Laya adapter (classification only)
                                                            |
                                                            v
                                                   validated SearchPlan
                                                            |
                                                            v
                                                Rails Search Orchestrator
                                                  |         |         |
                                                  v         v         v
                                               DB/cache  Active Job  SerpApi
                                                  \         |         /
                                                   v        v        v
                                          normalized snapshots -> history, metrics, UI
```

Security boundary: the frontend talks only to Rails, and only Rails calls upstream services. Background jobs bypass Laya.

## Quality checklist (definition of done)

| # | Question | Planned approach | Stage | Status |
|---|----------|------------------|-------|--------|
| 1 | Are **successful, error, and empty** API responses each handled? | Handle missing or empty `organic_results`; detect error payloads even on HTTP 200; classify auth, quota, rate-limit, transient network, timeout, invalid request, and unexpected schema errors; one fixture test per case | 3 | [x] |
| 2 | Does the service keep working when the search API is **slow or failing**? | Connect/read timeouts; retry only transient errors with capped exponential backoff and jitter (respect `Retry-After`); on final failure keep the last successful snapshot, **marked stale**; never retry invalid credentials or malformed requests | 4 | [x] |
| 3 | Are **duplicate search requests prevented** and **usage managed**? | Idempotent jobs keyed by a fingerprint of normalized query + engine + locale + settings + time window; block concurrent duplicate runs; cache TTL with `cache_hit` tracking; daily request budget and concurrency limits (quota read from the account/docs, never hardcoded) | 4 | [x] |
| 4 | Is **rank change** computed accurately? | Canonicalize hostnames, define and test exact vs. subdomain matching; absent rank is `NULL` ("not found in retrieved window"), never 0; compare only snapshots with equivalent search settings; lower number = better position | 3 | [x] |
| 5 | Is the core logic **tested with RSpec** (or similar)? | Unit tests for normalizer, domain matching, rank delta, fingerprint, plan validator, and budget rules; request/integration tests; provider adapter tests (success, empty, 4xx, 429, 5xx, timeout, malformed JSON); Laya adapter tests (unsupported intent, prompt injection, timeout, disabled) | all, 7 | [ ] |
| 6 | Can **execution time and failure causes** be inspected in logs? | `SearchRun` stores start/end, upstream latency, error category, and cache source; structured logs; p50/p95, success/failure counts, errors by category, cache hit rate, and upstream call count via `/api/v1/metrics/summary`; search terms and secrets minimized in logs | 4 | [x] |
| 7 | Does the core flow work **without Laya**? | With `LAYA_ENABLED=false`: add keyword, search, snapshot, compare, and scheduled checks all work; natural language returns only a safe fallback (clarification request) | 5 | [ ] |
| 8 | Is a natural-language plan **validated and confirmed** before it runs? | Allow-list of known fields; no arbitrary search on low confidence or invalid output; costly or broad searches require user confirmation | 5 | [ ] |

## Scope

**In the MVP:** keyword CRUD, Google organic search via SerpApi, normalization and snapshot storage, rank history, scheduled checks (Active Job), cache/retry/budget, metrics, optional Laya intent classification, Next.js dashboard.

**Out of scope:** Jev, multi-agent orchestration, autonomous browsing, proxy/CAPTCHA circumvention, custom scrapers, large-scale crawling, billing, multi-tenant RBAC. The app also makes no unsupported LLM claims about results and no "global ranking" claims: a rank is a value for a specific query, location, device, and snapshot time.

## Stack (finalized after checking installed versions)

- Backend: Ruby, Rails (API mode), Active Record, PostgreSQL, RSpec (or Minitest, one only)
- Jobs: Active Job on Solid Queue (stored in the same PostgreSQL database, no Redis), with recurring tasks for scheduled checks
- Search: SerpApi, via the official Ruby client if verified compatible, otherwise a small HTTPS adapter with explicit timeouts
- Frontend: Next.js, React, TypeScript, Tailwind
- Intent classification (optional): Laya, isolated behind a `LayaClassifier` interface (findings in [docs/discovery.md](docs/discovery.md))

## Roadmap

After each stage, a summary and a proposed commit message are produced, and the next stage starts only after confirmation.

| Stage | Content | Status |
|-------|---------|--------|
| 0 | Discovery and baseline (`docs/discovery.md`) | Done |
| 1 | Ruby/Rails basics, Rails API scaffold, `/health` | Done |
| 2 | Domain model, REST API (keyword CRUD) | Done |
| 3 | SerpApi integration, normalization, rank tracking | Done |
| 4 | Scheduled jobs, caching, resilience, metrics | Done, awaiting confirmation |
| 5 | Laya pre-classifier integration | Pending |
| 6 | Next.js dashboard | Pending |
| 7 | Tests, A/B/C comparison, benchmarks | Pending |
| 8 | Deployment and operations | Pending |

## Local setup (verified on macOS, Homebrew Ruby 4.0.3, Rails 8.1.4, PostgreSQL 16)

```bash
brew services start postgresql@16
gem install rails
# Homebrew Ruby's gem executables are not on PATH by default:
export PATH="$(gem env gemdir)/bin:$PATH"

cd backend
cp .env.example .env          # placeholders only; real values stay in the git-ignored .env
bundle install
bin/rails db:create db:migrate

bundle exec rspec             # tests
bundle exec rubocop           # lint
bin/rails server              # API + background worker (Solid Queue runs inside Puma in development)
                              # then: curl localhost:3000/health
```

`GET /health` returns `200 {"status":"ok","database":"up"}`, or `503 {"status":"degraded","database":"down"}` when the database is unreachable (the underlying error is logged by class only, never returned). Rails' built-in `GET /up` also remains.

## API

Keyword CRUD under `/api/v1/keywords`; asynchronous searches with `POST/GET /api/v1/keywords/:id/searches`; `GET /api/v1/keywords/:id/rank_history`; `GET /api/v1/metrics/summary`. All with validation, pagination, and a shared JSON error format. Full contract, failure mapping, retry/cache/budget rules, and limitations: [docs/api-contract.md](docs/api-contract.md).

A search does not call SerpApi inside the request. It is queued, a worker performs the call, and you poll the run:

```bash
curl -s -X POST localhost:3000/api/v1/keywords/1/searches    # 202 {"meta":{"outcome":"enqueued"},"data":{"id":7,"status":"queued",...}}
curl -s localhost:3000/api/v1/keywords/1/searches/7          # a few seconds later: "status":"succeeded" (or "failed" + error_category)
curl -s -X POST localhost:3000/api/v1/keywords/1/searches    # again within the TTL: 200 {"meta":{"outcome":"cache_hit"},...}, no SerpApi call
curl -s -X POST "localhost:3000/api/v1/keywords/1/searches?refresh=true"   # skip the cache
curl -s localhost:3000/api/v1/metrics/summary                # p50/p95, error categories, cache hit rate, budget, queue
bin/rails searchops:serpapi_quota                            # SerpApi plan and remaining searches (free Account API)
```

To run a real search, put your SerpApi key in `backend/.env` as `SERPAPI_API_KEY` and restart the server. Real SerpApi calls are counted by `SEARCH_MAX_REQUESTS_PER_DAY` (retries included); cache hits are free. Scheduled keywords (`daily` or `weekly`) are searched automatically by a recurring job while the server or `bin/jobs` is running. There is no authentication yet, so run it locally only.

## Configuration

Real values go only in `backend/.env`, which is never committed. `backend/.env.example` contains placeholders only. The search-related variables are placeholders until they are used in Stages 3–5.

```dotenv
SERPAPI_API_KEY=replace_me
LAYA_ENABLED=false
SEARCH_MAX_REQUESTS_PER_DAY=5
SEARCH_CACHE_TTL_SECONDS=3600
SEARCH_MAX_CONCURRENCY=2
SEARCH_MAX_KEYWORDS=50
```

Development and test use the local PostgreSQL through `config/database.yml` (`searchops_development`, `searchops_test`). `DATABASE_URL` is an optional override.

> Test results for search logic, benchmarks, and screenshots will be added here only after they have been verified.
