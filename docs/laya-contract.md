# Laya integration contract

Laya is an optional natural-language **intent classifier**. It never searches, never generates text the app acts on, and the core search flow works with `LAYA_ENABLED=false`. This file records what Laya's HTTP server actually accepts and returns, what was confirmed against a running instance, and what was not.

## Sources and how each fact was established

| Source | Used for |
|---|---|
| `laya/serve.py` on GitHub (`NandhaKishorM/laya`, `main`), read 2026-10-26 | Routes, request and response fields, limits, error codes, environment variables |
| The installed package, `laya 0.4.15` from PyPI (Apache-2.0, Python >= 3.10) | Checkpoint registry in `laya/router.py` |
| A running `laya-serve` on this machine (Apple M4 Pro, MPS) | Everything marked "verified live" below |

The GitHub file is `main`, not necessarily byte-identical to the 0.4.15 wheel. Anything the app depends on was therefore checked against the running 0.4.15 server, and `LAYA_LIVE=1 bundle exec rspec --tag laya_live` repeats that check.

PyPI's metadata names "Convai Innovations" as author and links the Hugging Face project (`convaiinnovations/laya`) as homepage, not the GitHub repository. The GitHub README links to the same Hugging Face organization, so the two are consistent, but the PyPI-to-GitHub link rests on the README rather than on package metadata.

## What Laya is and is not

- A non-autoregressive classifier: it answers typed questions about a text in one forward pass and produces **no generated text**. Its output is a label and numbers, which the app checks against a closed list. Nothing it returns is an instruction.
- **No entity extraction.** The README describes none. Country, domain, and search-query extraction are done by rules (`Intent::Extractor`), not by Laya. Free text such as the keyword is never taken from Laya's output.
- Korean is **not mentioned** in Laya's README. It was measured instead (see `docs/intent-eval.md`).
- Checkpoints in the Hugging Face bundle `convaiinnovations/laya`: `english`, `multilingual`, `typed-decisions`. `english` collapses outside English by the README's own account, and on the dev split scored 58.6% against 72.9% for `multilingual` even on English sentences, so the app uses **`multilingual`**. `typed-decisions` is fine-tuned for four unrelated workflows (customer service, invoices, security incidents, agent traces) and is not downloaded.

## HTTP contract (from `serve.py`)

| Method and path | Auth | Notes |
|---|---|---|
| `POST /v1/systemone` | Bearer, if `LAYA_API_KEY` is set | One state, several questions. **Used by the app.** |
| `POST /v1/systemone/batch` | same | Many states, same questions. Not used by the app. |
| `GET /health` | open | Liveness; full detail (loaded checkpoints, revisions, device) when no key is set or a valid token is sent |
| `GET /docs`, `/openapi.json` | none | Not served when `LAYA_API_KEY` is set |

Request (`POST /v1/systemone`):

```json
{
  "model": "multilingual",
  "state": "the sentence",
  "questions": {
    "intent": {
      "type": "choice",
      "instructions": "What does the user want to do?",
      "criteria": { "organic_rank_tracking": "...", "job_search": "...", "search_history": "...", "unsupported": "..." }
    }
  }
}
```

Response (shortened from the recording in `spec/fixtures/laya/systemone_response.json`):

```json
{
  "model": "laya-rl-agent",
  "answers": {
    "intent": {
      "type": "choice",
      "choice": "unsupported",
      "probabilities": { "organic_rank_tracking": 0.0217, "job_search": 0.3931, "search_history": 0.0205, "unsupported": 0.5646 },
      "confidence": 0.3849, "answer_confidence": 0.5646, "action": { "act_probability": 1.0 }, "x_jev_confidence": 0.4195
    }
  },
  "usage": { "input_tokens": 254, "output_tokens": 0 },
  "routing": { "model": "multilingual", "repo": "convaiinnovations/laya/multilingual", "reason": "explicit model='multilingual'" }
}
```

The app uses `answers.intent.choice` and `answers.intent.probabilities`. Its confidence is the **probability of the chosen label**, which equals `answer_confidence`. Laya's README says to gate on the `confidence` field instead, and in the recorded response the two differ (0.3849 against 0.5646). On the dev split (n=70) the two separate correct from wrong answers equally well (AUC 0.877 for the chosen probability, 0.873 for `confidence`; identical accuracy at 80%, 70%, and 60% coverage), so the simpler chosen probability is used, and the threshold in this repo was measured on it. The two are on different scales (0.34 to 1.0 against 0.07 to 1.0 on dev), so a threshold cannot be moved from one to the other.

The body is validated before use: every label must be present with a number in 0..1, the chosen label must be one of the four known intents, and the body must be smaller than 256 KB; anything else is rejected as `invalid_response` and treated like an outage.

Limits from `serve.py`: 64 questions per request, 50,000 characters of state, 2 MiB body, 100 options per choice, 16 concurrent requests past auth, body read timeout 10 s. A single request with one 4-option question is far inside all of them. A 70-sentence batch with several questions was refused with HTTP 413 during the evaluation, so the evaluation sends sentences one at a time.

Error responses (`detail` string): 400 bad input, 401 bad bearer token, 408 slow body, 413 limit exceeded, 422 refused field or question error, 500 `inference failed`, 503 `server busy` with `Retry-After: 1`. The client maps them to `bad_request`, `auth`, `bad_request`, `bad_request`, `bad_request`, `server_error`, `busy`.

Environment variables read by the server include `LAYA_HOST` (default `0.0.0.0`; `scripts/laya-serve.sh` overrides it to `127.0.0.1`), `LAYA_PORT` (default 8000; the script uses 8765), `LAYA_MODELS`, `LAYA_DEFAULT_MODEL`, `LAYA_MAX_LOADED`, `LAYA_API_KEY`, `LAYA_REVISION` (pins the checkpoint commit), and `LAYA_DEVICE`. Start command: `python -m laya.serve`.

## Verified live (laya 0.4.15, checkpoint revision `7b928d8`, `multilingual`, MPS)

- The request above is accepted and answered as shown. `choice` takes `criteria` as an object of label to description.
- A `noul` (yes/no) question works with `instructions` only; `serve.py` does not show its request shape. It is no longer sent: its scores added false positives and found nothing the word lists missed (see the evaluation).
- Latency per request after warm-up: p50 about 28 ms, p95 about 40 ms, max about 185 ms in the evaluation runs. The first request after start took about 0.6 to 2.5 s.
- Loading the checkpoint prints `RuntimeWarning: this checkpoint ships invalid temperatures or values outside [0.5, 5]; using choice:11+=0.100582808`. Laya falls back to a default, and its own README says such a fallback "does not establish calibrated confidence". **The probabilities are therefore not calibrated**, which is why the confidence threshold was measured rather than assumed. A probability of 1.000 was seen for sentences that are plainly typical, and 0.9994 for one that was wrong.
- `/health` reports the loaded checkpoints, their revisions, the device, and CPU-fallback counters.

## Not verified live

- Bearer authentication (`LAYA_API_KEY`): the client sends `Authorization: Bearer <key>` and is tested against a mock only.
- The 503 busy path, the 413 path for the app's own requests, and behavior with `LAYA_JEV_STRICT`.
- Behavior of any checkpoint other than `multilingual` through the app.

## How the app uses it

- `Intent::LayaClassifier` posts one request per sentence to `LAYA_URL` (an operator setting, never a request parameter) with a 4 s read timeout and a 2 s connect timeout, no retries. Any failure, timeout, or malformed answer becomes a fallback response ("unavailable") and never an error for the user.
- The sentence is sent **masked**: the quoted keyword and any domain are replaced by `KEYWORD` and `DOMAIN` first (`Intent::Extractor#masked_text`). The topic of a keyword is not the intent: `'react developer jobs'` inside a rank-check sentence had pulled Laya to `job_search` at 0.985. As a side effect the user's keyword and domain are never sent to Laya.
- Confidence below `LAYA_MIN_CONFIDENCE` (default 0.7) produces no plan, only a clarification response with the two likeliest intents.

## Running it locally

```bash
scripts/laya-setup.sh     # isolated virtualenv in tools/laya (git-ignored), laya==0.4.15, downloads english + multilingual
scripts/laya-serve.sh     # http://127.0.0.1:8765, multilingual only, revision pinned
# in backend/.env: LAYA_ENABLED=true, then restart Rails
```

Model files go to `tools/laya/hf_cache` unless your shell already sets `HF_HUB_CACHE`/`HF_HOME`, in which case that cache is reused (here: `/Volumes/DevWork/work/AI/huggingface`, where the checkpoints already existed, so nothing new was downloaded). The two needed checkpoints are about 1.45 GB (`english` 804 MB, `multilingual` 647 MB). Weights are safetensors files, not pickles.

Upgrading Laya: change `LAYA_VERSION` and the pinned revision, rerun `LAYA_LIVE=1 bundle exec rspec --tag laya_live`, re-record `spec/fixtures/laya/systemone_response.json`, and rerun the evaluation before trusting the old threshold.
