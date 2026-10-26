import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { mockApi, options, renderApp } from "@/test/utils";
import type { IntentPlan, Options } from "@/lib/types";
import { confirmPayload, editsFrom, prefillHref, sourceLabel, PlanResult } from "./plan-result";

const opts = options() as unknown as Options;

const ready: IntentPlan = {
  id: 7, status: "ready", reason: null, next_step: "confirm",
  plan: { intent: "organic_rank_tracking", engine: "google", query: "react developer jobs", country: "ph", language: "en", target_domain: "example.com", compare_previous: true, only_new: false },
  requires_confirmation: true, missing: [], errors: {},
  fields: {
    intent: { source: "laya", confidence: 0.9985 }, query: { source: "rule", evidence: "react developer jobs" }, country: { source: "rule", evidence: "philippines" },
    language: { source: "rule", derived_from: "country" }, target_domain: { source: "rule", evidence: "example.com" },
    compare_previous: { source: "rule" }, only_new: { source: "default" },
  },
  candidates: [], keyword_candidates: [], query_suggestions: [], history: { keyword_id: null, snapshots: 0 }, notes: ["baseline_only"],
  classifier: { name: "laya", enabled: true, version: "laya:multilingual@0.4.15@7b928d8", intent: "organic_rank_tracking", confidence: 0.9985, min_confidence: 0.7, latency_ms: 31,
    probabilities: { organic_rank_tracking: 0.9985, job_search: 0.0003, search_history: 0.0008, unsupported: 0.0004 } },
  structured_input: null, execution: null, created_at: "2026-10-26T00:00:00Z", confirmed_at: null,
};
const withPlan = (overrides: Partial<IntentPlan>): IntentPlan => ({ ...ready, ...overrides });

function show(plan: IntentPlan, onUpdated = vi.fn()) {
  renderApp(<PlanResult plan={plan} options={opts} onUpdated={onUpdated} />);
  return onUpdated;
}

describe("a ready plan", () => {
  it("shows the status, the intent, and that nothing has run yet", () => {
    show(ready);
    expect(screen.getByText("Ready to confirm")).toBeInTheDocument();
    expect(screen.getByText("Check a rank")).toBeInTheDocument();
    expect(screen.getByText(/Nothing has run yet/)).toBeInTheDocument();
  });

  it("fills the form from the plan and says where each value came from", () => {
    show(ready);
    expect(screen.getByRole("textbox", { name: /Query/ })).toHaveValue("react developer jobs");
    expect(screen.getByRole("textbox", { name: /Query/ })).toHaveAccessibleDescription("from your text: react developer jobs");
    expect(screen.getByRole("combobox", { name: /Country/ })).toHaveValue("ph");
    expect(screen.getByRole("combobox", { name: /Language/ })).toHaveAccessibleDescription("derived from the country");
  });

  it("calls a required field required, without the keyword form's contradicting '(optional)'", () => {
    show(ready);
    expect(screen.getByText("Target domain")).toBeInTheDocument();
    expect(screen.queryByText(/optional/i)).not.toBeInTheDocument();
  });

  it("explains the flags without printing an empty quote", () => {
    show(ready);
    expect(screen.getByText("(matched words in your sentence)")).toBeInTheDocument();
    expect(screen.getByText("(default (not mentioned))")).toBeInTheDocument();
    expect(screen.queryByText(/from your text: \)/)).not.toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: /Compare with the earlier result/ })).toBeChecked();
    expect(screen.getByRole("checkbox", { name: /Only new or changed items/ })).not.toBeChecked();
  });

  it("says that only a baseline can be made when there is nothing to compare with", () => {
    show(ready);
    expect(screen.getByText(/creates a baseline/)).toBeInTheDocument();
  });

  it("states what confirming costs", () => {
    show(ready);
    expect(screen.getByText(/runs one search/)).toBeInTheDocument();
  });

  it("sends the (possibly edited) fields when confirmed, then shows the outcome", async () => {
    const executed = withPlan({ status: "executed", next_step: "none", execution: { kind: "search", keyword_id: 9, keyword_created: true, run_id: 4, search_outcome: "enqueued" } });
    const fetchMock = mockApi({ "POST /api/v1/intent/plan/7/confirm": { body: { data: executed } } });
    const onUpdated = show(ready);

    await userEvent.clear(screen.getByRole("textbox", { name: /Query/ }));
    await userEvent.type(screen.getByRole("textbox", { name: /Query/ }), "vue developer jobs");
    await userEvent.click(screen.getByRole("checkbox", { name: /Only new/ }));
    await userEvent.click(screen.getByRole("button", { name: "Confirm and search" }));

    await waitFor(() => expect(onUpdated).toHaveBeenCalledWith(executed));
    const body = JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body));
    expect(body).toEqual({ plan: { query: "vue developer jobs", country: "ph", language: "en", target_domain: "example.com", compare_previous: true, only_new: true } });
    expect(await screen.findByText("Plan confirmed.")).toBeInTheDocument();
  });

  it("shows the classifier's reasoning on request", async () => {
    show(ready);
    await userEvent.click(screen.getByText("How this was classified"));
    expect(screen.getByText(/Check a rank \(99\.9%\)/)).toBeInTheDocument();
    expect(screen.getByText("laya:multilingual@0.4.15@7b928d8")).toBeInTheDocument();
    expect(screen.getByText("31 ms")).toBeInTheDocument();
  });
});

describe("a plan with missing details", () => {
  const missing = withPlan({
    status: "needs_clarification", reason: "missing_fields", next_step: "complete_fields",
    plan: { intent: "organic_rank_tracking", engine: "google", target_domain: "example.com", compare_previous: false, only_new: false },
    missing: ["query", "country", "language"], notes: [],
    fields: { ...ready.fields, query: { source: "missing" }, country: { source: "missing" }, language: { source: "missing" } },
  });

  it("asks for each missing field once, without repeating a hint", () => {
    show(missing);
    expect(screen.getByText(/some details are not in your sentence/)).toBeInTheDocument();
    expect(screen.getAllByText("Not found in your sentence: please fill this in.")).toHaveLength(3);
    // The same fact is not also printed as a grey hint under each field.
    expect(screen.queryByText("not found in your sentence")).not.toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: /Query/ })).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByRole("combobox", { name: /Country/ })).toHaveAttribute("aria-invalid", "true");
  });

  it("keeps the button off until every required field is filled", async () => {
    show(missing);
    const button = screen.getByRole("button", { name: "Complete and search" });
    expect(button).toBeDisabled();
    expect(screen.getByText(/Fill in the query, country, language, and target domain/)).toBeInTheDocument();

    await userEvent.type(screen.getByRole("textbox", { name: /Query/ }), "my tips");
    expect(button).toBeDisabled();
    await userEvent.selectOptions(screen.getByRole("combobox", { name: /Country/ }), "kr");
    await userEvent.selectOptions(screen.getByRole("combobox", { name: /Language/ }), "ko");
    expect(button).toBeEnabled();
  });

  it("does not submit while incomplete, even with Enter", async () => {
    const fetchMock = mockApi({});
    show(missing);
    await userEvent.type(screen.getByRole("textbox", { name: /Query/ }), "tips{enter}");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("offers a suggested query when there is one", async () => {
    show({ ...missing, query_suggestions: ["Senior React Developer"] });
    await userEvent.click(screen.getByRole("button", { name: "Senior React Developer" }));
    expect(screen.getByRole("textbox", { name: /Query/ })).toHaveValue("Senior React Developer");
  });
});

describe("a plan that was not understood well enough", () => {
  const lowConfidence = withPlan({
    status: "needs_clarification", reason: "low_confidence", next_step: "rephrase_or_use_structured_input", plan: null, notes: [], fields: {},
    candidates: [{ intent: "unsupported", probability: 0.587 }, { intent: "organic_rank_tracking", probability: 0.386 }],
    structured_input: { endpoint: "/api/v1/keywords", fields: [], prefill: { country: "kr", language: "ko", target_domain: "example.com" } },
  });

  it("makes no plan: no confirm button, no form", () => {
    show(lowConfidence);
    expect(screen.queryByRole("button", { name: /Confirm|Complete and search/ })).not.toBeInTheDocument();
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
    expect(screen.getByText(/not sure what you meant/)).toBeInTheDocument();
  });

  it("lists the likeliest meanings with their probability", () => {
    show(lowConfidence);
    expect(screen.getByText("Something else (58.7%)")).toBeInTheDocument();
    expect(screen.getByText("Check a rank (38.6%)")).toBeInTheDocument();
  });

  it("offers the keyword form, prefilled with what could be read", () => {
    show(lowConfidence);
    const link = screen.getByRole("link", { name: "Open the keyword form" });
    expect(link).toHaveAttribute("href", "/keywords?country=kr&language=ko&target_domain=example.com");
  });
});

describe("other outcomes", () => {
  it("reports an out-of-scope request without a way to run it", () => {
    show(withPlan({ status: "unsupported", reason: "out_of_scope", next_step: "none", plan: null, fields: {}, notes: [] }));
    expect(screen.getByText("Not supported")).toBeInTheDocument();
    expect(screen.getByText(/not something this app does/)).toBeInTheDocument();
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Open the keyword form" })).not.toBeInTheDocument();
  });

  it("keeps a job search read-only and says why it cannot run", () => {
    show(withPlan({
      status: "unsupported", reason: "engine_not_available", next_step: "none", notes: ["engine_not_implemented"],
      plan: { intent: "job_search", engine: "google_jobs", query: "Senior React Developer", country: "ph", language: "en", compare_previous: true, only_new: true },
    }));
    expect(screen.getByText(/need the google_jobs engine/)).toBeInTheDocument();
    expect(screen.getByText("Senior React Developer")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Confirm|search/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
  });

  it.each([
    ["laya_disabled", /switched off/],
    ["classifier_timeout", /did not answer in time/],
    ["classifier_unavailable", /laya-serve\.sh/],
    ["classifier_busy", /busy/],
    ["classifier_invalid_response", /could not be trusted/],
  ])("explains why nothing was understood: %s", (reason, text) => {
    show(withPlan({
      status: "unavailable", reason, next_step: "use_structured_input", plan: null, fields: {}, notes: [], classifier: { name: "laya", enabled: false },
      structured_input: { endpoint: "/api/v1/keywords", fields: [], prefill: { query: "react", target_domain: "react.dev" } },
    }));
    expect(screen.getByText(text)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Open the keyword form" })).toHaveAttribute("href", "/keywords?query=react&target_domain=react.dev");
  });

  it("links a history request to the keyword and says it is read-only", () => {
    show(withPlan({ plan: { intent: "search_history", engine: "google", keyword_id: 3, compare_previous: false, only_new: false }, requires_confirmation: false, notes: [] }));
    expect(screen.getByRole("link", { name: "Open the history" })).toHaveAttribute("href", "/keywords/3");
    expect(screen.getByText(/read-only/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Confirm/ })).not.toBeInTheDocument();
  });

  it("links to the list when the history covers every keyword", () => {
    show(withPlan({ plan: { intent: "search_history", engine: "google", compare_previous: false, only_new: false }, requires_confirmation: false, notes: [] }));
    expect(screen.getByRole("link", { name: "Open the history" })).toHaveAttribute("href", "/keywords");
  });

  it("lists the keywords to choose from when several match", () => {
    show(withPlan({
      status: "needs_clarification", reason: "ambiguous_keyword", next_step: "complete_fields", plan: { intent: "search_history", engine: "google", compare_previous: false, only_new: false },
      keyword_candidates: [{ id: 1, query: "react developer", target_domain: "react.dev" }, { id: 2, query: "react developer", target_domain: null }], notes: [],
    }));
    expect(screen.getAllByRole("link", { name: "react developer" })).toHaveLength(2);
    expect(screen.getByText(/More than one tracked keyword matches/)).toBeInTheDocument();
  });
});

describe("after confirming", () => {
  const executed = (execution: IntentPlan["execution"]) => withPlan({ status: "executed", next_step: "none", execution, confirmed_at: "2026-10-26T00:01:00Z" });

  it("links to the new keyword", () => {
    show(executed({ kind: "search", keyword_id: 9, keyword_created: true, run_id: 4, search_outcome: "enqueued" }));
    expect(screen.getByText("Done")).toBeInTheDocument();
    expect(screen.getByText("A new keyword was created.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Open the keyword" })).toHaveAttribute("href", "/keywords/9");
    expect(screen.queryByRole("button", { name: /Confirm/ })).not.toBeInTheDocument();
  });

  it.each([
    ["enqueued", /Search queued/], ["deduplicated", /already queued or running/], ["cache_hit", /SerpApi was not called/],
  ] as const)("says what happened to the search: %s", (outcome, text) => {
    show(executed({ kind: "search", keyword_id: 9, keyword_created: false, run_id: 4, search_outcome: outcome }));
    expect(screen.getByText("An existing keyword was used.")).toBeInTheDocument();
    expect(screen.getByText(text)).toBeInTheDocument();
  });
});

describe("when confirming fails", () => {
  async function confirmWith(status: number, body: unknown) {
    mockApi({ "POST /api/v1/intent/plan/7/confirm": { status, body } });
    const onUpdated = show(ready);
    await userEvent.click(screen.getByRole("button", { name: "Confirm and search" }));
    return onUpdated;
  }

  it("explains an exhausted budget with the numbers and keeps the plan", async () => {
    const onUpdated = await confirmWith(429, { error: { code: "search_budget_exceeded", message: "x", details: { limit: 5, used: 5 } } });
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("The daily search budget is used up.");
    expect(alert).toHaveTextContent("5 of 5 searches used today.");
    expect(onUpdated).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Confirm and search" })).toBeEnabled();
  });

  it("lists the invalid fields the API reports", async () => {
    await confirmWith(422, { error: { code: "invalid_plan", message: "x", details: { errors: { country: "not_allowed" }, missing: ["target_domain"] } } });
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("The plan is not valid yet.");
    expect(screen.getByText("country: not_allowed")).toBeInTheDocument();
    expect(screen.getByText("target_domain: still missing")).toBeInTheDocument();
  });

  it("tells the user to configure SerpApi", async () => {
    await confirmWith(503, { error: { code: "search_provider_not_configured", message: "x" } });
    expect(await screen.findByRole("alert")).toHaveTextContent(/SERPAPI_API_KEY/);
  });

  it("survives an unreachable server", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("offline"); }));
    show(ready);
    await userEvent.click(screen.getByRole("button", { name: "Confirm and search" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(/could not be reached/);
  });
});

describe("helpers", () => {
  const t = (key: string, vars?: Record<string, string | number>) => `${key}${vars ? JSON.stringify(vars) : ""}`;

  it("confirmPayload leaves blanks out so the API reports them as missing", () => {
    expect(confirmPayload({ query: " a ", country: "", language: "en", location: "", target_domain: "x.com", compare_previous: false, only_new: true }))
      .toEqual({ compare_previous: false, only_new: true, query: "a", language: "en", target_domain: "x.com" });
  });

  it("editsFrom copes with a plan without fields", () => {
    expect(editsFrom(withPlan({ plan: null }))).toEqual({ query: "", country: "", language: "", location: "", target_domain: "", compare_previous: false, only_new: false });
  });

  it("prefillHref ignores empty values and encodes the rest", () => {
    expect(prefillHref(undefined)).toBe("/keywords");
    expect(prefillHref({ query: "a b&c", country: undefined })).toBe("/keywords?query=a+b%26c");
  });

  it("sourceLabel picks the right wording", () => {
    expect(sourceLabel(t as never, undefined)).toBeNull();
    expect(sourceLabel(t as never, { source: "rule" })).toBe("plan.source.cue");
    expect(sourceLabel(t as never, { source: "rule", evidence: "x" })).toContain("plan.source.rule");
    expect(sourceLabel(t as never, { source: "rule", derived_from: "country" })).toContain("plan.source.derived");
    expect(sourceLabel(t as never, { source: "missing" })).toBe("plan.source.missing");
    expect(sourceLabel(t as never, { source: "default" })).toBe("plan.source.default");
  });
});
