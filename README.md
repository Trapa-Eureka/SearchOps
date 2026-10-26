# SearchOps — Search Intelligence & API Monitoring

**English** · [Korean](README.ko.md)

> **Status: Stage 6 (Next.js dashboard) is complete: six screens (overview, keywords, results with rank history, API health, natural-language planner) in English and Korean, showing only real data from the Rails API. Verified with 726 backend specs, 281 frontend tests (including an axe accessibility check of every screen), and by driving the real UI against a real Rails server and a real local Laya server. Natural-language planning accuracy is modest (intent 74 to 77% on small author-labeled sets, Korean 62 to 64%), so most sentences end in a clarification rather than a ready plan; see [docs/intent-eval.md](docs/intent-eval.md). `job_search` is understood but cannot run yet (no `google_jobs` engine).**
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
| 7 | Does the core flow work **without Laya**? | With `LAYA_ENABLED=false`: add keyword, search, snapshot, compare, and scheduled checks all work; natural language returns only a safe fallback (clarification request) | 5 | [x] |
| 8 | Is a natural-language plan **validated and confirmed** before it runs? | Allow-list of known fields; no arbitrary search on low confidence or invalid output; costly or broad searches require user confirmation | 5 | [x] |

## Scope

**In the MVP:** keyword CRUD, Google organic search via SerpApi, normalization and snapshot storage, rank history, scheduled checks (Active Job), cache/retry/budget, metrics, optional Laya intent classification, Next.js dashboard.

**Out of scope:** Jev, multi-agent orchestration, autonomous browsing, proxy/CAPTCHA circumvention, custom scrapers, large-scale crawling, billing, multi-tenant RBAC. The app also makes no unsupported LLM claims about results and no "global ranking" claims: a rank is a value for a specific query, location, device, and snapshot time.

## Stack (finalized after checking installed versions)

- Backend: Ruby, Rails (API mode), Active Record, PostgreSQL, RSpec (or Minitest, one only)
- Jobs: Active Job on Solid Queue (stored in the same PostgreSQL database, no Redis), with recurring tasks for scheduled checks
- Search: SerpApi, via the official Ruby client if verified compatible, otherwise a small HTTPS adapter with explicit timeouts
- Frontend: Next.js (App Router), React, TypeScript, Tailwind, SWR for data fetching, Vitest + Testing Library + axe-core for tests. It talks only to Rails through a same-origin `/api` proxy, so there is no CORS setup and no credential in the browser
- Intent classification (optional): Laya (`multilingual` checkpoint) running locally as `laya-serve`, behind `Intent::LayaClassifier`. Contract and what was verified: [docs/laya-contract.md](docs/laya-contract.md). Measured accuracy: [docs/intent-eval.md](docs/intent-eval.md)

## Roadmap

After each stage, a summary and a proposed commit message are produced, and the next stage starts only after confirmation.

| Stage | Content | Status |
|-------|---------|--------|
| 0 | Discovery and baseline (`docs/discovery.md`) | Done |
| 1 | Ruby/Rails basics, Rails API scaffold, `/health` | Done |
| 2 | Domain model, REST API (keyword CRUD) | Done |
| 3 | SerpApi integration, normalization, rank tracking | Done |
| 4 | Scheduled jobs, caching, resilience, metrics | Done |
| 5 | Laya pre-classifier integration | Done |
| 6 | Next.js dashboard | Done, awaiting confirmation |
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

## Dashboard

```bash
cd frontend
cp .env.example .env.local    # API_BASE_URL=http://127.0.0.1:3000 (server-side only, never sent to the browser)
pnpm install
pnpm dev                      # http://localhost:3001; start the Rails server (port 3000) first

pnpm test                     # 281 tests, including axe accessibility checks
pnpm typecheck && pnpm lint
pnpm build && pnpm start
```

Screens: **Overview** (success rate, median/p95 latency, SerpApi calls, cache hit rate, budget, keywords that need attention), **Keywords** (create, edit, pause, search now), **Keyword detail** (rank chart and table, search runs, stored results with the target domain highlighted), **API health** (request timeline, failures by cause, retries, queue and worker state, stale keywords), **Planner** (sentence, proposed plan, edit and confirm, or a clarification). The UI is available in English and Korean.

Behaviours worth knowing: a **lower rank number is better** and the chart says so; a rank that was not found is drawn in its own "Not found" band and is never shown as rank 0; stale data is labelled with the time of the last good result; a cache hit shows the time the data was originally captured; status is always given in words and a symbol, not by colour alone. Every number comes from the Rails API; with no data the dashboard shows dashes and an explanation, not made-up values. It reads two endpoints added for it: `GET /api/v1/options` (allowed values and limits) and `GET /api/v1/searches` (recent runs across keywords). There is no authentication yet, so run it locally only.

## API

Keyword CRUD under `/api/v1/keywords`; asynchronous searches with `POST/GET /api/v1/keywords/:id/searches`; `GET /api/v1/keywords/:id/rank_history`; `GET /api/v1/metrics/summary`; `GET /api/v1/options` and `GET /api/v1/searches` for the dashboard. All with validation, pagination, and a shared JSON error format. Optional natural-language planning with `POST /api/v1/intent/plan` and `POST /api/v1/intent/plan/:id/confirm`. Full contract, failure mapping, retry/cache/budget rules, and limitations: [docs/api-contract.md](docs/api-contract.md).

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

### Natural-language planning (optional, needs Laya)

Laya only classifies the sentence; Rails extracts the details, validates a closed set of plan fields, and executes only after you confirm. With Laya off (the default) or down, the endpoint answers with a structured-input fallback and the rest of the API is unaffected.

```bash
scripts/laya-setup.sh          # once: isolated Python env in tools/laya, laya==0.4.15 (reuses the model cache if you already have the checkpoints, about 1.45 GB otherwise)
scripts/laya-serve.sh          # in its own terminal: http://127.0.0.1:8765, multilingual checkpoint
# backend/.env: LAYA_ENABLED=true   (then restart the Rails server)

curl -s -X POST localhost:3000/api/v1/intent/plan -H 'Content-Type: application/json' \
  -d '{"text":"Where does example.com rank for '"'"'react developer jobs'"'"' in the Philippines? Compare with last week"}'
# 201 {"data":{"id":12,"status":"ready","next_step":"confirm","plan":{"intent":"organic_rank_tracking","query":"react developer jobs","country":"ph","language":"en","target_domain":"example.com","compare_previous":true,...},...}}
curl -s -X POST localhost:3000/api/v1/intent/plan/12/confirm    # creates the keyword and queues one search (budget and cache apply)
LAYA_ENABLED=true bin/rails "searchops:intent_eval[dev]"        # accuracy report on the labeled sentences
```

What to expect: the project's own example sentence (Korean, job search) is read as `unsupported` at 0.56 by the real model and ends in a clarification with the country, query, and flags pre-filled, not in a plan. Job searches cannot be confirmed yet.

## Configuration

Real values go only in `backend/.env`, which is never committed. `backend/.env.example` contains placeholders only. The search-related variables are placeholders until they are used in Stages 3–5.

```dotenv
SERPAPI_API_KEY=replace_me
LAYA_ENABLED=false            # optional natural-language planning; the core flow never needs it
SEARCH_MAX_REQUESTS_PER_DAY=5
SEARCH_CACHE_TTL_SECONDS=3600
SEARCH_MAX_CONCURRENCY=2
SEARCH_MAX_KEYWORDS=50
LAYA_URL=http://127.0.0.1:8765
LAYA_MIN_CONFIDENCE=0.7
INTENT_RETENTION_DAYS=30
```

Development and test use the local PostgreSQL through `config/database.yml` (`searchops_development`, `searchops_test`). `DATABASE_URL` is an optional override.

> Test results for search logic, benchmarks, and screenshots will be added here only after they have been verified.
