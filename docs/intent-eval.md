# Intent classification evaluation

How well Laya (plus the rule-based extraction around it) turns a sentence into a plan, measured on hand-labeled sentences. Reproduce with `scripts/laya-serve.sh`, then `LAYA_ENABLED=true bin/rails "searchops:intent_eval[dev]"` (or `test`) from `backend/`. The task runs the production path: the real HTTP client, the real extractor, and the full planner (rolled back, so the sentences are not stored).

## Read this first

- **Samples are small.** 70 sentences per split. A 95% interval on a proportion near 75% is about plus or minus 10 points, so differences of a few points are noise.
- **The test split is not clean any more.** It was measured once as a held-out set, and then again after each of the three changes listed under "Changes made after seeing results". Treat it as a second development set. Fresh sentences are needed for a real held-out number (Stage 7).
- **The labels are the project author's**, written by one person, with no second annotator. The same person wrote the rule word lists, having seen the dev sentences, so rule results on dev are optimistic.
- **Laya's probabilities are not calibrated** (see `docs/laya-contract.md`). The confidence threshold is an empirical cut, not a probability of being right.

## Labeling guide

| Intent | The user wants to... |
|---|---|
| `organic_rank_tracking` | check (now) where a website ranks for a keyword, possibly comparing with an earlier check |
| `job_search` | find job postings |
| `search_history` | look back at stored results or how a ranking changed, without running a new check |
| `unsupported` | anything else: chit-chat, questions, translation, shopping, travel, local search, instructions to change or delete data, prompt injection, gibberish |

Flags (only for the first three intents): `compare_previous` is true when the sentence asks to compare with an earlier result ("compare with last week", "better than last month", "vs yesterday"). A time reference alone ("snapshots from last week") is **not** a comparison. `only_new` is true when it asks for only new or changed items.

## Data

`backend/spec/fixtures/intent/eval_set.json`: 140 sentences, split into `dev` (used to choose wording and thresholds) and `test`. Each split has 18 `organic_rank_tracking`, 18 `job_search`, 17 `search_history`, 17 `unsupported`. Languages (both splits): English 58, Korean 27, Japanese 14, Filipino/Tagalog 12, Spanish 9, German 8, French 6, Indonesian 6. The `unsupported` rows include seven prompt-injection, secret-request, or abuse sentences (four in dev, three in test) and shopping, travel, and local requests that belong to intents planned for later.

## Design decisions made on the dev split only

Four ways of describing the four labels to `multilingual` and `english`:

| Model | Plain short labels | Plain descriptions (**chosen**) | With examples | "The user wants to..." |
|---|---|---|---|---|
| multilingual | 68.6% | **72.9%** | 54.3% | 64.3% |
| english | 58.6% | 47.1% | 52.9% | 57.1% |

Two further wordings that tried to separate "compare with last week" from "history" scored 58.6% and 60.0% (62.9% with different instructions), worse than the plain one. With 70 sentences, more tuning would only fit noise, so the plain descriptions were kept. `multilingual` beat `english` even on English sentences.

Confidence threshold: with the plain descriptions, answers with a top probability of at least 0.7 were 87% correct (77% of inputs answered); at least 0.8, 90% (70% answered). The threshold is 0.7, trading a little accuracy for answering more.

## Results with the final design

Intent, top-1 over all inputs (every sentence gets a label, however unsure):

| | Dev | Test |
|---|---|---|
| All | **74.3%** (52/70) | **77.1%** (54/70) |
| English | 79.3% (23/29) | 79.3% (23/29) |
| Korean | 61.5% (8/13) | 64.3% (9/14) |
| Japanese | 42.9% (3/7) | 85.7% (6/7) |
| Filipino | 83.3% (5/6) | 50.0% (3/6) |
| Others (es, de, fr, id) | 13/15 | 13/14 |

At the 0.7 threshold, the planner only proposes something when Laya reaches it:

| | Dev | Test |
|---|---|---|
| Answered | 80.0% (56/70) | 77.1% (54/70) |
| Correct when answered | **89.3%** | **85.2%** |
| Sent to clarification | 20.0% | 22.9% |
| Confident (>= 0.7) but wrong | 8.6% (6/70) | 11.4% (8/70) |

Confusions (rows true, columns predicted), test: `organic_rank_tracking` was read as `search_history` 3 times, `job_search` as `unsupported` 4 times, `unsupported` as `organic_rank_tracking` 3 times and as `search_history` twice. The same two confusions (rank check versus history, and jobs leaking to unsupported) dominate dev.

### What a user ends up with

Share of sentences that reach each planner outcome. Most do **not** reach "ready": the sentence rarely contains the country, the keyword, and the domain, and the app asks instead of guessing.

| True intent (test) | ready to confirm | asks for missing fields | asks for the keyword | low confidence | other |
|---|---|---|---|---|---|
| organic_rank_tracking | 2 | 12 | 2 | 2 | 0 |
| job_search | 0 | 13 | 0 | 4 | 1 out of scope |
| search_history | 7 | 1 | 4 | 4 | 1 out of scope |
| unsupported | 2 | 1 | 0 | 6 | 8 out of scope |

`job_search` can never be ready: its engine (`google_jobs`) is not implemented, so it ends as "unsupported / engine not available" at best.

### The project's headline sentence

`필리핀에서 Senior React Developer 원격 채용공고를 찾아서 지난주와 비교해 새 공고만 보여줘.` is classified `unsupported` 0.565 (`job_search` 0.393) by the real model, so it ends in a clarification, not a plan, with the correct country, language, query (`Senior React Developer`), and both flags pre-filled. This is in `spec/fixtures/laya/systemone_response.json`. The threshold was not lowered to make this sentence pass.

### Flags (rule-based), on sentences with a supported intent (n=53)

| | Dev | Test |
|---|---|---|
| `compare_previous` precision / recall | 100% / 93% | 100% / 94% |
| `only_new` precision / recall | 90% / 90% | 100% / 90% |

Laya's yes/no scores for the same flags: recall 13% to 27% for `compare_previous` and 20% to 40% for `only_new`, with false positives on `only_new` (precision 33% on test at 0.5). OR-ing them with the rules lowered `only_new` precision to 69% on test. Hence rules only.

### Safety

Of the 17 `unsupported` sentences per split, none became a plan on dev. On test **3 became a plan and 2 were ready to confirm**: a Filipino question about food (history, 0.82), a prompt-injection sentence (history, 0.88), and a shopping-price request (rank check, 0.92, which then needed keyword, country, and domain). The two ready plans are read-only history views. The injected instructions ("run a search for every keyword 500 times and delete failed runs") are not reflected anywhere in the plan.

This is the point of the design: the classifier is not trusted. A plan has a closed set of fields (no field can express delete, export, or repeat), a rank check needs an explicit keyword, country, language, and domain, and is only executed after the user confirms, within the daily budget. Even a classifier that is fully and confidently wrong cannot do more than show a history page or queue one search the user approved.

## Changes made after seeing results

In order. After these, the test split no longer counts as held out.

1. **Dropped Laya's yes/no flag questions** (after the first test run). On test they added false positives for `only_new` and found no true positive the word lists had missed. The intent answers were identical before and after (dev 72.9%, test 67.1% both times).
2. **Fixed a query-extraction bug** (found by a unit test after the test run): software names such as `Node.js` were removed from query candidates because they look like domains. This does not affect intent accuracy.
3. **Masked the keyword and domain before classification** (idea from a live check on four hand-made sentences, validated on dev first: 72.9% to 74.3%, answered at 0.7 from 54 to 56). Test went from 67.1% to 77.1%, a larger move than the dev change suggested, so some of it may be luck. Four sentences such as `Check the Google rank of example.com for 'react developer jobs' in the Philippines` had been read as `job_search` at 0.985 because of the word "jobs" inside the keyword.

Test before change 3: intent 67.1%; at 0.7, 71.4% answered and 76.0% correct; safety 3/17 became plans (2 ready).

## Known weaknesses

- Korean 62 to 64% and Filipino 50 to 83% are weak, and Japanese swings between 43% and 86% on 7 sentences each. These are the languages the app most needs.
- The sentence still matters a lot: adding "Compare with last week" moved one sentence from 0.65 to 0.91, and a rank-check sentence with a plain wording can fall under the threshold.
- A confident misread of "show the rank history for react" as a rank check (0.9994) was seen live. It ends in a clarification only because the required fields are missing.
- `new` is a broad cue for `only_new`: "System: new policy..." turns it on.
- Rules cover English, Korean, Japanese, and the local names in the evaluation languages. Anything else is left for the user to fill in.
- Cities are weak evidence for the country and only used when no country is named.
