# Discovery Report (Stage 0)

Date: 2026-10-26 · Scope: inspection only. No application code, no paid calls, no secrets.

## 1. Repository state

| Item | Finding |
|---|---|
| Path | `/Volumes/DevWork/work/search-ops` |
| Git | Initialized, branch `main`, **no commits yet**, git user `Trapa-Eureka` |
| Existing code | None (no Rails app, no `package.json`, no README before this stage) |
| Existing files | `CLAUDE.md` (implementation playbook; now git-ignored, stays on disk) |
| Added in Stage 0 | `.gitignore`, `README.md`, `docs/discovery.md` |

## 2. Environment (verified by running the commands)

| Tool | Version / status | Note |
|---|---|---|
| Ruby | 4.0.3 (2026-04-21) | Very new major. Compatibility with the chosen Rails and gems must be verified in Stage 1. |
| Bundler | 4.0.10 | |
| Rails | **Not installed** | `gem list -r` reports `rails 8.1.4` as latest on RubyGems. Whether it supports Ruby 4.0.3 is **unverified**. |
| Node | v24.12.0 | |
| npm / pnpm | 11.6.2 / 10.30.1 | `yarn` not installed. Package manager choice deferred to Stage 6 (pnpm available). |
| PostgreSQL | 16.15 (Homebrew), client installed | **Server is not running** (`pg_isready`: no response on `/tmp:5432`). Must be started before Stage 1 migrations. |
| RSpec | Not installed | Test framework to be chosen in Stage 1 (RSpec is the stated preference in the project docs). |
| SerpApi Ruby gem | `serpapi 1.0.3` exists on RubyGems | Compatibility with Ruby 4.0.3 and its error/timeout behavior is **unverified**. Fallback is a small HTTPS adapter. |
| SerpApi credentials | **Not configured** (`SERPAPI_API_KEY` unset in the shell; checked yes/no only) | Stage 3 live calls need a key and explicit approval to spend quota. Fixtures work without one. |

## 3. SerpApi (from https://serpapi.com/search-api)

Confirmed by the official page:
- Endpoint: `https://serpapi.com/search` (GET). `api_key` and `q` are required; `engine` defaults to `google`.
- Locale parameters: `location` (city-level recommended; cannot be combined with `uule`/`lat`/`lon`), `gl` (2-letter country), `hl` (language), `output` (`json` default).
- `organic_results[]` items include `position`, `title`, `link`, `displayed_link`, `snippet`.
- Cache: on by default; a cached result is served only when the query and **all** parameters match exactly, expires after 1 hour, and cached searches do not count toward the monthly quota. `no_cache=true` disables it (do not combine with `async`).

Not found on that page (must be verified elsewhere before relying on them):
- Error payload format (`error` key and HTTP status mapping), rate-limit headers / `Retry-After`.
- How to read current account quota/usage (the Account API is documented separately).
- Exact `search_metadata` / `search_parameters` fields (the sample on the page showed `search_information`).
- `google_jobs` parameters and fields (needed only post-MVP).

Planning consequence: the app's "local cache" and "SerpApi-side cache" are different layers and `cache_hit` should record which one served a result. The SerpApi cache expiry (1 hour) is a default to re-check, not a constant to hardcode.

## 4. Laya (from https://github.com/NandhaKishorM/laya)

What the README states (project's own claims; **not benchmarked by us**):
- A multilingual, non-autoregressive "System 1" decision engine: answers typed questions about a text in one forward pass, **no text generation**. Python 3.10+, Apache-2.0. Install: `python -m pip install laya`; checkpoints download from Hugging Face on first use (about 2.3 GB for all three).
- Interfaces: Python library (`Router().predict(state, questions)`), `laya` CLI, and an HTTP server `laya-serve` (FastAPI) with `POST /v1/systemone` and `/v1/systemone/batch`. Auth is a bearer key (`LAYA_API_KEY` on the MCP client). There is also an MCP server and TypeScript/Rust/Go/Java/.NET ports.
- Question types: `choice` (pick one label, returns probabilities + confidence), `score` (ordinal), `noul` (yes/no probability). `decide()` / `laya_decide` fills a JSON schema (enums, booleans, bounded integers) with per-field confidence.
- Checkpoints: `laya` (English, 421M), `laya-multilingual` (322M, 100+ languages claimed), `laya-typed-decisions` (421M).
- Reported latency on a Tesla T4: about 33–40 ms for 1 question; scales with the number of questions per call.

What this means for SearchOps:
- **Intent classification is supported** (`choice`), so `intent` ∈ {`organic_rank_tracking`, `job_search`, `search_history`, `unsupported`} maps naturally to one `choice` question, and `engine` / `compare_previous` / `only_new` can map to further `choice`/`noul` questions or a `decide()` schema.
- **Free-text entity extraction is not described.** The `query` string (e.g. "Senior React Developer remote") and `country` cannot be assumed to come from Laya. Plan: a deterministic Rails-side parser/validator for these fields, or ask the user to confirm/edit them. Do not claim Laya extracts them.
- **Korean is not mentioned in the README.** The base `laya` checkpoint "collapses outside English"; only `laya-multilingual` is a candidate, and Korean accuracy must be measured on our own labeled set (Stage 7) before trusting it. The project's Korean example input is therefore an open risk.
- **Known failure modes listed by the README:** negation in labels, boolean-word labels being followed instead of descriptions, high raw confidence on unsupported languages (Khmer: 0.000 accuracy at 95.2% confidence), position bias on `score`. Raw confidence is not proof of calibration, so low-confidence fallback needs a threshold chosen from our eval set and strict Rails-side validation regardless.
- **Operational cost:** a local Python service plus ~GBs of model weights and either CPU/MPS/CUDA. This is why Laya stays optional and behind an adapter.
- The README does not document the HTTP request/response schema or error codes; the contract is said to be at the top of `laya/serve.py` in the repo. **Next step before Stage 5:** clone or read that file and record the exact wire format here.
- The README says `laya-serve` is wire-compatible with the hosted Jev API. Jev remains out of scope for this project.

## 5. Facts vs. assumptions

Confirmed: items listed in sections 1–4 as "confirmed" or "verified".

Assumptions (unverified, to resolve in the stage noted):
1. Rails 8.1.x runs on Ruby 4.0.3 with the gems we need (Stage 1).
2. The `serpapi` gem works on this Ruby and exposes usable timeout/error handling; otherwise use a small HTTPS adapter (Stage 3).
3. Laya's HTTP contract can be called from Rails with a bounded timeout and its confidence output is usable as a gate (Stage 5).
4. `laya-multilingual` handles Korean well enough for this use (Stage 5 / 7).
5. A free SerpApi plan is enough for fixtures + a few live smoke calls. Current quota must be read from the account, not assumed (Stage 3).

## 6. Unresolved questions (need the user's input when the stage needs them)

1. Do you have a SerpApi account / API key, and may live calls be used for a small number of smoke tests? (Needed at Stage 3.)
2. Should Laya run locally (Python + model download of about 2.3 GB) or is the Laya path allowed to remain a tested stub until later? (Needed at Stage 5.)
3. Test framework: RSpec (project docs prefer it). Confirm at Stage 1.
4. Job backend for production (Solid Queue vs. Sidekiq/Redis) depends on the hosting choice. Deferred to Stage 4/8.

## 7. Chosen setup (proposed, to be confirmed per stage)

| Area | Proposal | Verify at |
|---|---|---|
| Backend | Rails API mode in `backend/`, PostgreSQL, RSpec | Stage 1 |
| Frontend | Next.js + TypeScript + Tailwind in `frontend/` | Stage 6 |
| Search provider | `SearchProvider` interface, `SerpApiSearchProvider` first | Stage 3 |
| Intent | `LayaClassifier` interface + fake for tests; real adapter after reading `laya/serve.py` | Stage 5 |
| Config | Env vars + `.env.example` with placeholders only | Stage 1 |

Proposed directory structure (adapt as the code grows):

```text
search-ops/
├── README.md
├── .gitignore
├── docs/
│   ├── discovery.md            # this file
│   ├── architecture.md         # later
│   ├── api-contract.md         # Stage 2+
│   ├── benchmarks.md           # Stage 7
│   └── operations.md           # Stage 8
├── backend/                    # Rails API (Stage 1)
│   ├── .env.example
│   ├── app/controllers/api/v1/
│   ├── app/models/
│   ├── app/services/
│   │   ├── search_orchestrator.rb
│   │   ├── search_plan_validator.rb
│   │   └── providers/serpapi_search_provider.rb
│   ├── app/jobs/
│   └── spec/
└── frontend/                   # Next.js dashboard (Stage 6)
```

## 8. Smallest safe next step (Stage 1 entry conditions)

1. Start PostgreSQL locally (for example `brew services start postgresql@16`) and confirm `pg_isready`.
2. Install Rails and verify it boots on Ruby 4.0.3 (`gem install rails`), then scaffold `rails new backend --api --database=postgresql --skip-test`. If Rails 8.1 does not work on Ruby 4.0.3, report the exact error and options (for example a Ruby version manager) instead of working around it silently.
3. Add RSpec, a linter (RuboCop), `/health` endpoint, and a request spec.

## 9. Stage 1 update (2026-10-26)

Resolved from the assumptions and entry conditions above:
- **Rails 8.1.4 works on Ruby 4.0.3** (`require "rails"` loads; the generated app boots; specs, RuboCop, and Brakeman pass). Assumption 1 is confirmed.
- PostgreSQL 16 is now running as a Homebrew service (`brew services start postgresql@16`).
- Homebrew Ruby's gem executable directory is not on `PATH`, so `rails` was not found after `gem install rails`. Workaround used: `export PATH="$(gem env gemdir)/bin:$PATH"`. No shell profile was modified.
- `gem install rails` pulled `rdoc 8.1.0` next to the default `rdoc 7.0.3`, which prints harmless "already initialized constant" warnings in some commands.
- Generated with `rails new backend --api --database=postgresql --skip-test --skip-git --skip-gitignore --skip-kamal --skip-thruster --skip-docker --skip-ci --skip-solid --skip-active-storage --skip-action-mailbox --skip-action-text --skip-action-mailer`. Queue backend (Solid Queue vs. Sidekiq) and deployment files (Docker/Kamal) are deliberately deferred to Stages 4 and 8.
- Test framework: RSpec (`rspec-rails`). Lint: `rubocop-rails-omakase`. Security: Brakeman and bundler-audit are in the Gemfile. `dotenv-rails` loads `backend/.env`.

Still unverified: `serpapi` gem compatibility with Ruby 4.0.3 (Stage 3), Laya HTTP contract and Korean accuracy (Stage 5).

## 10. Stage 2 update (2026-10-26)

- Schema: `keywords`, `search_runs`, `search_results`, `rank_snapshots`, `intent_requests` (details in [api-contract.md](api-contract.md)). Unique index on keyword search settings uses `NULLS NOT DISTINCT`, so PostgreSQL 15+ is required (local is 16.15). Check the managed-database version in Stage 8.
- `Keyword` stores `country` (SerpApi `gl`) and `language` (`hl`) instead of a single `locale` column, because both parameters are documented separately by SerpApi.
- Only `engine=google` is allowed until a provider implements another engine. The planner contract in `CLAUDE.md` mentions `google_jobs`; it is added to the allow-list when its provider support and fields are verified.
- Authentication is intentionally not implemented yet. This is a Stage 8 prerequisite before any public exposure.

## 11. Stage 3 update (2026-10-26)

Resolved from the open items in sections 3 and 5:
- **Error format (confirmed from https://serpapi.com/api-status-and-error-codes):** body `{"error": "<message>"}`. 400 missing parameter, 401 invalid key, 403 forbidden, 404 not found, 429 hourly throughput limit **or** exhausted searches (told apart only by the message), 500/503 server error. Empty results are HTTP 200 with `search_metadata.status` `Success` and `error` "Google hasn't returned any results for this query." `search_metadata.status` values: `Queued`, `Processing`, `Success`, `Error`.
- **Not documented, so not relied on:** `Retry-After`, the hourly limit's value or message text, HTTP 408, any "cached" indicator in the response.
- **Quota check:** Account API `GET https://serpapi.com/account.json?api_key=...` returns `searches_per_month`, `plan_searches_left`, `total_searches_left`, `this_month_usage`, `this_hour_searches`, `account_rate_limit_per_hour`, and is free (not counted toward the quota). It is not wired in yet; Stage 4 can use it to read the real budget instead of trusting `SEARCH_MAX_REQUESTS_PER_DAY`.
- **`serpapi` gem 1.0.3 (source read, not adopted):** loads on Ruby 4.0.3 only if its HTTP.rb dependency installs. Its persistent mode (the default) does not apply the `timeout` option, and it raises on any top-level `error`, which would turn SerpApi's empty-result response into a failure. Decision: a small `Net::HTTP` adapter with explicit timeouts (assumption 2 resolved).
- **Real-world check:** one call with a deliberately invalid key against the live endpoint returned HTTP 401 with the documented body, which confirms TLS, the request format, and the 401 classification. No quota was used and no real credential was sent.
- **Still not run:** a live search with a real key (needs a key and approval to use quota). All search fixtures are hand-written from documented fields.
- Two real defects were found by tests while building this stage and fixed: `NUL` bytes reached a uniqueness query (Stage 2), and a rolled-back result record was re-inserted through has_many autosave when the failed run was saved (orchestrator now reloads the run before recording a failure).

## 12. Stage 4 update (2026-10-26)

- **Queue backend: Solid Queue 1.7.0** (the Sidekiq alternative would add a Redis dependency before the hosting is chosen). Its tables live in the primary PostgreSQL database through a normal migration (`CreateSolidQueueTables`, copied from `bin/rails solid_queue:install` without `force: :cascade`). The installer assumes a separate `queue` database; that assumption and its `connects_to` line were removed. In development Solid Queue runs inside Puma (`plugin :solid_queue`, default on in development); elsewhere set `SOLID_QUEUE_IN_PUMA` explicitly or run `bin/jobs`. Specs use the `:test` adapter.
- **SerpApi cache indicator:** not documented. `search_metadata` is documented with `id`, `status`, `created_at`, `processed_at`, `json_endpoint`, and `total_time_taken`, but no field says a result was served from SerpApi's one-hour cache. So only the local cache is tracked (`cache_source: app`); `serpapi` is never reported. A live response could be inspected to check for an undocumented field (needs a real call).
- **Pagination:** only `start` (result offset; `10` is the second page) is documented. `num` is not on the page, the maximum is not stated, and it is not stated whether each page counts as a separate search. Paging is therefore not implemented; the rank window stays the first response (5 organic results for the one query tried live).
- **Account API:** wired into `bin/rails searchops:serpapi_quota`, which prints only quota fields. Not called automatically, so the local daily budget is still a guard and not the source of truth.
- **Retry-After:** not documented by SerpApi. Parsed (delay-in-seconds form only) and honored when present, capped at 300 s.
- **Verified live without spending quota:** the job pipeline (enqueue, de-duplication, Solid Queue worker, real HTTPS call, 401 classified as `auth` with no retry, metrics, recurring tasks registered) was run against the real endpoint with a deliberately invalid key injected into the server process. The retry and success paths in the queue were verified with mocked HTTP only.
- Bugs found by tests while building this stage: a spec-only trap where a memoized `let` hid later responses (three times), and the need for the `:test` adapter's job list to be cleared between examples. In the code: legacy Stage 3 runs had `upstream_calls = 0` (their real SerpApi call was invisible to the budget), fixed by `BackfillSearchRunCounters`.

## 13. Stage 5 update (2026-10-26)

Resolved from the open items in sections 4, 5, and 6:
- **Laya HTTP contract:** read from `laya/serve.py` (`POST /v1/systemone`, request `state` + `questions`, response `answers.<id>` with `choice`, `probabilities`, `confidence`) and verified against a running laya 0.4.15. Details, limits, and what was not verified live (bearer auth, the 503 path): [laya-contract.md](laya-contract.md). `noul` request shape is not in `serve.py`; `instructions` alone works, but those questions were dropped.
- **Korean:** not mentioned by Laya. Measured: 62 to 64% intent accuracy (74 to 77% overall), the weakest of the larger groups. [intent-eval.md](intent-eval.md).
- **Install:** `laya[serve]==0.4.15` into `tools/laya/.venv` (git-ignored) with Python 3.12. The checkpoints were already in the shell's `HF_HUB_CACHE` (`/Volumes/DevWork/work/AI/huggingface`), so nothing was downloaded. Only `english` and `multilingual` (about 1.45 GB) are used; `typed-decisions` is fine-tuned for four unrelated workflows. `multilingual` beat `english` even on English sentences. Loading prints a warning that the checkpoint ships invalid temperatures, so the probabilities are not calibrated; the threshold was measured instead of assumed.
- **Assumptions closed:** (3) Laya's contract is callable with a bounded timeout, and its confidence works as a gate only roughly (about 85 to 89% correct when it answers at 0.7, on small sets); (4) `multilingual` does not handle Korean well enough to act on its own, which is why every plan needs confirmation and low-confidence sentences are asked about.
- **Design driven by the measurements:** Laya classifies the intent only. Country, domain, and keyword candidates, and the two flags, come from rules because Laya has no extraction and its yes/no scores added false positives. The keyword and domain are masked before classification because a word like "jobs" inside the keyword had flipped rank checks to job searches. A plan has a closed field set and runs only after confirmation.
- **Findings worth knowing:** the project's own example sentence is read as `unsupported` at 0.56 and ends in a clarification; `job_search` cannot run because `google_jobs` is not implemented; the held-out test split was reused three times and no longer counts as held out.
- **Bugs found by tests/checks while building this stage:** `LAYA_ENABLED=maybe` enabled Laya (ActiveModel boolean casting is fail-open); a Zeitwerk constant defined in the wrong file would raise `NameError` in development but not in production; `ftp://` URLs crashed instead of being rejected; `Node.js`-style names were stripped from query candidates; keyword errors had symbol keys unlike every other error.
