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

## 14. Stage 6 update (2026-10-26)

- **Stack (verified by install and build):** Next.js 16.4.3 (App Router, Turbopack), React 19.3, TypeScript 6, Tailwind 4, SWR 2.5.1, Vitest 4 + jsdom + Testing Library, axe-core 4.14.0, pnpm 10. The first install picked `next@16.4.0`, which `pnpm audit` flagged (critical RCE advisories); it was moved to 16.4.3 and the audit is clean.
- **Same-origin proxy:** `next.config.ts` rewrites `/api/*` to `API_BASE_URL` (server-side variable, not `NEXT_PUBLIC_`). The browser only ever calls its own origin, so there is no CORS and no credential or Rails address in the bundle. Checked by grepping the production bundle: the only match is the name `SERPAPI_API_KEY` inside a help message, no value.
- **Two endpoints added to Rails for the UI** (read-only, specs included): `GET /api/v1/options` (allowed values and limits, so the form never copies them) and `GET /api/v1/searches` (runs across keywords, for the timeline and error log). Contract: [api-contract.md](api-contract.md).
- **Chart:** a custom SVG instead of a chart library, because the axis is inverted (rank 1 at the top), "not found" needs its own band below the scale (never rank 0), the line must break at a missing rank, and each point needs a text alternative. A `<table>` with the same data sits beside it.
- **Polling:** SWR's function form of `refreshInterval` never starts its timer when the first evaluation returns 0, which left a freshly queued run showing "Queued" forever. `usePolledWhile` keeps the interval in state instead; a regression test fails on the old implementation (checked by temporarily reverting it).
- **Accessibility:** axe-core runs over all five screens in both languages (colour contrast excluded because jsdom has no layout; `contrast.test.ts` checks the design tokens against 4.5:1 in both themes instead). axe found two real defects, both fixed: `<p>` inside a `<dl>` group (metric hints are now `<dd>`), and two landmarks with the same name (scrollable table regions now say "(scrolls sideways)"). Mobile width (375 px) was measured with no horizontal page scroll on every page.
- **Verified against the real stack, not only mocks:** the UI was driven in a headless browser against a real Rails server, Solid Queue, a scratch database with sample rows, and the real local Laya server, with a deliberately fake SerpApi key so no quota was used. Planner flows checked: ready, low confidence, out of scope, missing fields then complete and confirm. The real development database and the real SerpApi key were not touched.
- **Not verified:** a successful live SerpApi search through the UI (needs the real key and quota), a dark-theme visual pass (only the token contrast is tested), and any browser other than headless Chromium.
- **Backend adjustments made along the way:** query suggestions now come only from quoted phrases and Latin runs in a CJK sentence (the whole-sentence fallback produced useless suggestions); the macOS fork-safety note for `DATABASE_URL` is in `backend/.env.example`.

## 15. Stage 6 redesign (2026-10-26)

The first dashboard worked but looked generic: every region was the same rounded card, headline numbers were an undifferentiated grid, and status was shown with text glyphs. Two reference designs were supplied in `docs/ref/` (a logistics dashboard, `ui01.webp`, and an API-monitoring dashboard, `ui92.webp`; the second file is named `ui92` on disk).

- **Feasibility of ui01:** not adopted as the structure. Its centre is a photo of a truck with floating cards, a distribution map, and a driver card; SearchOps has no image or geographic data for them, so they would be decoration or empty space. Its soft raised "selected" pill, count-carrying segmented tabs, and a row of selectable items fit and were taken (filter tabs with real counts; a keyword switcher on the detail page).
- **ui92 as the structure:** sidebar navigation, header with a period control, a row of headline numbers, a stacked-bar chart, and a dense table with a mini bar strip per row. Things in it with no counterpart here were left out rather than faked: workspace switcher, team/billing/integrations, tracing, SSL expiry, Apdex, customize/export, per-site favicons (which would also make the browser call third parties), command-palette search.
- **Backend added for real data:** the `series` time series in `GET /metrics/summary`; `activity` on keywords (`KeywordActivity`, fixed number of queries for a page); `meta.counts` on `GET /searches`. Contract: [api-contract.md](api-contract.md). The series adds up to `requests.total` (spec).
- **Accessibility of the new parts:** each chart outcome has a colour and its own SVG pattern, the drawing is hidden from assistive technology and a table carries the same numbers, the run strip has a text summary, nav badges have text for screen readers, and the colour tokens are tested for 4.5:1 text contrast and 3:1 for control borders and chart colours in both themes (`contrast.test.ts`, which also caught that its own token regex ignored names with digits). axe passes on every screen in both languages.
- **Bugs found while doing it:** the visually hidden chart table widened the page on phones (a table ignores the 1px width of `.sr-only`; wrapped in a div); the action buttons of the keyword table were cut off at 1280 px (icons below 1536 px, words for screen readers and tooltips); `Add a keyword` appeared as both the card title and the button.
- **Checked visually** (headless Chromium against a scratch database with sample data and a fake SerpApi key): desktop 1280 and 1440, phone 390 (no horizontal scroll on any page), Korean, and the dark tokens. The sample data is only in the scratch database, never in the repository or the real development database.
- **Not verified:** a real browser's own dark-mode switch (dark tokens were injected), browsers other than Chromium, and live SerpApi data in the new views.

## 16. Stage 7 update (2026-10-26)

- **Coverage was measured, not assumed.** SimpleCov (opt-in, `COVERAGE=1`) gave 95.9% of lines and 94.2% of branches before this stage's tests. The uncovered code that mattered was written as tests: the `LAYA_URL` scheme check (only http/https), validation of a plan's `location` (type, length, control characters), refusals in the confirmation path, the lost-race case in the enqueuer, and malformed Laya answers. A few remaining branches are defensive and unreachable from outside (for example every country in the extractor's word list is also an allowed country). Now 858 backend specs, 95.9% of lines and 91.3% of branches (the new benchmark library counts too).
- **End-to-end specs** (`spec/e2e`, 15 examples) for the three modes. They were checked by mutation: eight single-line defects each made them fail. One check was wrong at first (the mutation edited a comment that contained the same text); it was caught by the control and redone.
- **Held-out set.** The old test split had been reused three times, so 80 new sentences were written after the design was frozen and measured once: intent accuracy **71.2%** (Korean 46.7%), confident and wrong 20%. Not tuned on afterwards. [intent-eval.md](intent-eval.md).
- **Benchmark harness** (`lib/search_ops_benchmark`, `searchops:benchmark`): real Rails stack and Laya, a seeded fake provider, deterministic per search so the modes are comparable and paired. It refuses any database not named `*_bench`. One seam was added to the application for it: `ExecuteSearchJob.provider_factory`, replaceable, defaulting to the real provider (specs). SerpApi was **not called at all** (the user chose the fake provider only; three earlier real calls gave the 900 ms median assumption). Results: [benchmarks.md](benchmarks.md).
- **Findings that were not obvious beforehand**, all in benchmarks.md and intent-eval.md: natural language completes no extra task and adds about 85 ms per task; Laya's latency is 72 ms on rank-check sentences but 19 to 21 ms on others (the earlier 21 ms figure was optimistic); a hung Laya costs the full 4 s timeout per sentence and there is no circuit breaker; history sentences that mention rank are read as rank checks (11 of 20); the extractor does not recognize domains with uncommon TLDs (`.so`, `.studio`) and ignores an explicit "English results"; the first request to a cold Laya can exceed the timeout.
- **Not done, on purpose:** no real SerpApi measurement (no quota used), no load or concurrency test, no change to the classifier or rules after seeing the held-out result. Hypotheses for improving them are listed in benchmarks.md and need a new held-out set.
- **Environment note for the next person:** `bundle exec` prints rdoc "already initialized constant" warnings on this machine (two rdoc versions); they are harmless. Bootsnap's compile cache can hide a same-length edit made within the same second, which matters only for mutation testing (set `DISABLE_BOOTSNAP=1`).

## 17. Checklist audit (2026-10-26)

Each row of the README quality checklist was re-checked against the code and the specs, not against the plan text.

- **Rows 1, 2, 4, 5, 7, 8: confirmed** with specific specs (error categories and fixtures, backoff with jitter and cap, `Retry-After`, stale marking, subdomain-versus-look-alike matching, plan and confirmation rules, the end-to-end journeys).
- **Row 3: wording corrected.** The fingerprint covers query, engine, locale, and location. It does not contain a time window, as the plan text said; the window is the cache TTL, and duplicates among queued or running runs are blocked by a unique index. The concurrency limit is checked as configuration (limit 2, one shared key); enforcing it is Solid Queue's job and is not exercised by a spec.
- **Row 6: a real defect, fixed.** The Rails request log printed every sentence given to the planner and every keyword, target domain, and location in clear text (`Parameters: {"text" => ...}`), and the SQL log printed the same values, including inside the JSON columns of plans and run metadata. This contradicted the checklist row and the claim in `api-contract.md` that sentences are never logged. It was reproduced first with a failing spec (4 of 5 examples), then fixed by extending `config.filter_parameters`, which Rails also applies to SQL values and `inspect`. Production logs at `info` would have carried the parameters line but not the SQL; the development and test logs carried both. 5 new specs; 863 in all.
- **Still true after the fix:** an exception message that quotes a database value (a unique-key violation names the key) can carry a search term if such an error is ever logged. Handled errors in this app are not logged that way today, but there is no spec for every path.
- **Not exercised by specs:** that Solid Queue really enforces `limits_concurrency` (it needs a running worker), and a load test of any kind.

