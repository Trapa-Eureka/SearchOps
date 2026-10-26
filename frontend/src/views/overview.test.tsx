import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { freshness, keyword, metrics, mockApi, page, renderApp, run } from "@/test/utils";
import { OverviewView } from "./overview";

const routes = (over: Record<string, unknown> = {}) => ({
  "GET /api/v1/metrics/summary": { body: { data: metrics(over) } },
  "GET /api/v1/keywords": { body: page([keyword(), keyword({ id: 2, query: "vue developer", freshness: freshness({ state: "stale", reason: "last_attempt_failed" }) })]) },
  "GET /api/v1/searches": { body: page([run({ id: 5, keyword: { id: 1, query: "react developer", country: "ph", language: "en", target_domain: "react.dev" } })]) },
});

const tile = (label: string) => screen.getByText(label, { selector: "dt" }).parentElement as HTMLElement;

describe("Overview", () => {
  it("shows the headline numbers with their context", async () => {
    mockApi(routes());
    renderApp(<OverviewView />);
    await screen.findByText("Success rate");

    expect(within(tile("Success rate")).getByText("80%")).toBeInTheDocument();
    expect(within(tile("Success rate")).getByText("8 succeeded · 2 failed")).toBeInTheDocument();
    expect(within(tile("Median latency")).getByText("900 ms")).toBeInTheDocument();
    expect(within(tile("p95 latency")).getByText("4.2 s")).toBeInTheDocument();
    expect(within(tile("p95 latency")).getByText("slowest 15 s")).toBeInTheDocument();
    expect(within(tile("SerpApi calls")).getByText("9")).toBeInTheDocument();
    expect(within(tile("Cache hit rate")).getByText("20%")).toBeInTheDocument();
    expect(within(tile("Today’s budget")).getByText("9 / 20")).toBeInTheDocument();
    expect(within(tile("Active keywords")).getByText("2 / 3")).toBeInTheDocument();
    expect(within(tile("Active keywords")).getByText("1 stale")).toBeInTheDocument();
  });

  it("lists only the keywords that need attention, with the last good time", async () => {
    mockApi(routes());
    renderApp(<OverviewView />);
    const attention = (await screen.findByRole("heading", { name: "Needs attention" })).closest("section") as HTMLElement;

    expect(await within(attention).findByRole("link", { name: "vue developer" })).toHaveAttribute("href", "/keywords/2");
    expect(within(attention).queryByRole("link", { name: "react developer" })).not.toBeInTheDocument();
    expect(within(attention).getByText(/Stale: last attempt failed/)).toBeInTheDocument();
  });

  it("says so when nothing is stale", async () => {
    mockApi({ ...routes(), "GET /api/v1/keywords": { body: page([keyword()]) } });
    renderApp(<OverviewView />);
    expect(await screen.findByText("Every tracked keyword is up to date.")).toBeInTheDocument();
  });

  it("never invents numbers when there is no data: dashes and reasons, not NaN or 0%", async () => {
    mockApi(routes({
      requests: { total: 3, by_status: { queued: 3, running: 0, succeeded: 0, failed: 0 }, by_trigger: { manual: 3, scheduled: 0 } },
      upstream: { calls: 0, retries: 0, runs_succeeded: 0, runs_failed: 0, success_rate: null, latency_ms: { samples: 0, p50: null, p95: null, max: null } },
      cache: { hits: 0, misses: 0, hit_rate: null, ttl_seconds: 3600 },
    }));
    renderApp(<OverviewView />);
    await screen.findByText("Success rate");

    expect(within(tile("Success rate")).getByText("—")).toBeInTheDocument();
    expect(within(tile("Success rate")).getByText("No finished searches in this period")).toBeInTheDocument();
    expect(within(tile("Median latency")).getByText("—")).toBeInTheDocument();
    expect(within(tile("Cache hit rate")).getByText("—")).toBeInTheDocument();
    expect(within(tile("Cache hit rate")).getByText("No searches in this period")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent("NaN");
    expect(document.body).not.toHaveTextContent("undefined");
  });

  it("welcomes a new user instead of showing a wall of zeros", async () => {
    mockApi({
      ...routes({ keywords: { total: 0, active: 0, scheduled: 0, stale: 0, no_data: 0 }, requests: { total: 0, by_status: { queued: 0, running: 0, succeeded: 0, failed: 0 }, by_trigger: { manual: 0, scheduled: 0 } } }),
      "GET /api/v1/keywords": { body: page([]) }, "GET /api/v1/searches": { body: page([]) },
    });
    renderApp(<OverviewView />);

    expect(await screen.findByText("Nothing is tracked yet")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Add a keyword" })).toHaveAttribute("href", "/keywords");
    expect(screen.getByRole("link", { name: "Open the planner" })).toHaveAttribute("href", "/planner");
    expect(screen.queryByText("Success rate")).not.toBeInTheDocument();
  });

  it("warns loudly when searches are queued but no worker is running", async () => {
    mockApi(routes({ queue: { queued: 4, running: 0, oldest_queued_age_seconds: 300, workers_alive: 0 } }));
    renderApp(<OverviewView />);
    await screen.findByText("Workers running");
    expect(within(tile("Workers running")).getByText(/4 queued but no worker is running/)).toBeInTheDocument();
  });

  it("flags a spent budget", async () => {
    mockApi(routes({ budget: { daily_limit: 5, used_today: 5, remaining_today: 0 } }));
    renderApp(<OverviewView />);
    await screen.findByText("Today’s budget");
    expect(within(tile("Today’s budget")).getByText(/Used up: new searches are refused until tomorrow/)).toBeInTheDocument();
  });

  it("loads the chosen period", async () => {
    const fetchMock = mockApi(routes());
    renderApp(<OverviewView />);
    await screen.findByText("Success rate");

    await userEvent.selectOptions(screen.getByRole("combobox", { name: "Period" }), "7d");

    await waitFor(() => expect(fetchMock.mock.calls.some(([url]) => String(url) === "/api/v1/metrics/summary?window=7d")).toBe(true));
  });

  it("shows an error with a working retry when the API is down", async () => {
    let up = false;
    mockApi({
      "GET /api/v1/metrics/summary": () => (up ? { body: { data: metrics() } } : { status: 503, body: { error: { code: "http_error", message: "down" } } }),
      "GET /api/v1/keywords": { body: page([]) }, "GET /api/v1/searches": { body: page([]) },
    });
    renderApp(<OverviewView />);

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("The request failed (HTTP 503).");
    up = true;
    await userEvent.click(within(alert).getByRole("button", { name: "Try again" }));

    expect(await screen.findByText("Success rate")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows the server-unreachable message when there is no connection", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("offline"); }));
    renderApp(<OverviewView />);
    expect(await screen.findAllByText(/could not be reached/)).not.toHaveLength(0);
  });

  it("is available in Korean", async () => {
    mockApi(routes());
    renderApp(<OverviewView />, { locale: "ko" });
    expect(await screen.findByText("성공률")).toBeInTheDocument();
    expect(screen.getByText("확인이 필요한 항목")).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent("Success rate");
  });
});
