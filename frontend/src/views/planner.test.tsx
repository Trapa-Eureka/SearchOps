import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { mockApi, options, renderApp } from "@/test/utils";
import { PlannerView } from "./planner";

const plan = (overrides: Record<string, unknown> = {}) => ({
  id: 5, status: "ready", reason: null, next_step: "confirm",
  plan: { intent: "organic_rank_tracking", engine: "google", query: "react developer", country: "ph", language: "en", target_domain: "react.dev", compare_previous: false, only_new: false },
  requires_confirmation: true, missing: [], errors: {}, fields: {}, candidates: [], keyword_candidates: [], query_suggestions: [], history: { keyword_id: null, snapshots: 0 }, notes: [],
  classifier: { name: "laya", enabled: true, version: "v", intent: "organic_rank_tracking", confidence: 0.99, min_confidence: 0.7, latency_ms: 30 }, structured_input: null, execution: null,
  created_at: "2026-10-26T00:00:00Z", confirmed_at: null, ...overrides,
});
const withOptions = (features = { intent_planning: true }) => ({ "GET /api/v1/options": { body: { data: { ...options(), features } } } });

describe("Planner", () => {
  it("starts empty with the submit disabled and examples to try", async () => {
    mockApi(withOptions());
    renderApp(<PlannerView />);

    expect(await screen.findByText("Natural-language planning is on")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Make a plan" })).toBeDisabled();
    expect(screen.getAllByRole("button", { name: /react|rank/i }).length).toBeGreaterThan(0);
    expect(screen.getByText("0 / 500")).toBeInTheDocument();
  });

  it("explains that planning is off and that the rest of the app still works", async () => {
    mockApi(withOptions({ intent_planning: false }));
    renderApp(<PlannerView />);

    expect(await screen.findByText("Natural-language planning is off")).toBeInTheDocument();
    expect(screen.getByText(/switched off/)).toBeInTheDocument();
  });

  it("fills the box from an example", async () => {
    mockApi(withOptions());
    renderApp(<PlannerView />);
    await screen.findByText("Natural-language planning is on");

    const example = screen.getAllByRole("listitem").find((item) => item.querySelector("button"))!.querySelector("button")!;
    await userEvent.click(example);

    expect(screen.getByRole("textbox", { name: /Your sentence/ })).toHaveValue(example.textContent);
    expect(screen.getByRole("button", { name: "Make a plan" })).toBeEnabled();
  });

  it("sends the sentence and shows the plan, with confirmation still pending", async () => {
    const fetchMock = mockApi({ ...withOptions(), "POST /api/v1/intent/plan": { status: 201, body: { data: plan() } } });
    renderApp(<PlannerView />);
    await screen.findByText("Natural-language planning is on");

    await userEvent.type(screen.getByRole("textbox", { name: /Your sentence/ }), "Where does react.dev rank for react developer in the Philippines?");
    await userEvent.click(screen.getByRole("button", { name: "Make a plan" }));

    expect(await screen.findByText("Ready to confirm")).toBeInTheDocument();
    expect(screen.getByText(/Nothing has run yet/)).toBeInTheDocument();
    const post = fetchMock.mock.calls.find(([, init]) => (init as RequestInit)?.method === "POST");
    expect(JSON.parse(String((post?.[1] as RequestInit).body))).toEqual({ text: "Where does react.dev rank for react developer in the Philippines?" });
  });

  it("blocks a sentence that is too long, and says by how much", async () => {
    mockApi({ ...withOptions(), "POST /api/v1/intent/plan": { body: { data: plan() } } });
    renderApp(<PlannerView />);
    await screen.findByText("Natural-language planning is on");

    await userEvent.click(screen.getByRole("textbox", { name: /Your sentence/ }));
    await userEvent.paste("x".repeat(501));

    expect(screen.getByText("501 / 500")).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: /Your sentence/ })).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByRole("button", { name: "Make a plan" })).toBeDisabled();
  });

  it("shows an error, and no stale plan, when the request fails", async () => {
    let fail = false;
    mockApi({ ...withOptions(), "POST /api/v1/intent/plan": () => (fail ? { status: 500, body: { error: { code: "http_error", message: "x" } } } : { status: 201, body: { data: plan() } }) });
    renderApp(<PlannerView />);
    await screen.findByText("Natural-language planning is on");
    const box = screen.getByRole("textbox", { name: /Your sentence/ });

    await userEvent.type(box, "first");
    await userEvent.click(screen.getByRole("button", { name: "Make a plan" }));
    await screen.findByText("Ready to confirm");

    fail = true;
    await userEvent.click(screen.getByRole("button", { name: "Make a plan" }));

    expect(await screen.findByText("The request failed (HTTP 500).")).toBeInTheDocument();
    expect(screen.queryByText("Ready to confirm")).not.toBeInTheDocument();
  });

  it("disables the button while it works, and re-enables it after", async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    mockApi({ ...withOptions(), "POST /api/v1/intent/plan": { body: { data: plan({ status: "unsupported", reason: "out_of_scope", plan: null, next_step: "none" }) } } });
    const inner = globalThis.fetch;
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
      if (init?.method === "POST") await gate;
      return inner(input, init);
    });
    renderApp(<PlannerView />);
    await screen.findByText("Natural-language planning is on");

    await userEvent.type(screen.getByRole("textbox", { name: /Your sentence/ }), "hello");
    await userEvent.click(screen.getByRole("button", { name: "Make a plan" }));
    expect(await screen.findByRole("button", { name: "Reading…" })).toBeDisabled();

    release();
    await waitFor(() => expect(screen.getByRole("button", { name: "Make a plan" })).toBeEnabled());
    expect(await screen.findByText("Not supported")).toBeInTheDocument();
  });
});
