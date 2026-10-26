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
