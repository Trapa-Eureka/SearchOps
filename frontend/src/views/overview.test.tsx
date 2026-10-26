import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { activity, freshness, keyword, metrics, mockApi, page, renderApp, series } from "@/test/utils";
import { OverviewView } from "./overview";

const routes = (over: Record<string, unknown> = {}) => ({
  "GET /api/v1/metrics/summary": { body: { data: metrics(over) } },
  "GET /api/v1/keywords": {
    body: page([
      keyword({ id: 1, query: "react developer" }),
      keyword({ id: 2, query: "vue developer", freshness: freshness({ state: "stale", reason: "last_attempt_failed" }) }),
    ]),
  },
});

const tile = (label: string) => screen.getByText(label, { selector: "dt span" }).closest("div") as HTMLElement;

describe("Overview", () => {
  it("shows the four headline numbers with their context", async () => {
    mockApi(routes());
    renderApp(<OverviewView />);
    await screen.findByText("Success rate");

    expect(within(tile("Success rate")).getByText("80%")).toBeInTheDocument();
    expect(within(tile("Success rate")).getByText("8 succeeded · 2 failed")).toBeInTheDocument();
    expect(within(tile("Median latency")).getByText("900 ms")).toBeInTheDocument();
    expect(within(tile("Median latency")).getByText("p95 latency 4.2 s · slowest 15 s")).toBeInTheDocument();
    expect(within(tile("Cache hit rate")).getByText("20%")).toBeInTheDocument();
    expect(within(tile("Today’s budget")).getByText("9 / 20")).toBeInTheDocument();
    expect(within(tile("Today’s budget")).getByText("11 left today")).toBeInTheDocument();
  });

  it("charts the requests over time, and the legend adds up to every request", async () => {
    mockApi(routes());
    renderApp(<OverviewView />);
    const card = (await screen.findByRole("heading", { name: "Search requests over time" })).closest("section") as HTMLElement;

    // succeeded 6, cache hit 2, failed 2 in the fixture: 10 requests, as in the tiles
    const legend = within(card).getAllByRole("listitem").map((item) => item.textContent);
    expect(legend).toEqual(["Answered by SerpApi6", "Answered from cache2", "Failed2", "Queued or running0"]);
  });

  it("gives screen readers the chart as a table of numbers", async () => {
    mockApi(routes());
    renderApp(<OverviewView />);
    const table = await screen.findByRole("table", { name: "Search requests per time slice, by outcome" });

    expect(within(table).getAllByRole("row")).toHaveLength(25); // header + 24 slices
    expect(within(table).getAllByRole("columnheader").map((header) => header.textContent)).toEqual([
      "Time slice", "Answered by SerpApi", "Answered from cache", "Failed", "Queued or running", "Total",
    ]);
  });

  it("says so, instead of drawing an empty chart, when nothing was requested in the period", async () => {
    mockApi(routes({ series: series() }));
    renderApp(<OverviewView />);
    expect(await screen.findByText("No searches were made in this period.")).toBeInTheDocument();
  });

  it("lists the tracked keywords with rank and recent searches, stale ones first, read-only", async () => {
    mockApi(routes());
    renderApp(<OverviewView />);
    const card = (await screen.findByRole("heading", { name: "Tracked keywords" })).closest("section") as HTMLElement;

    const links = await within(card).findAllByRole("link", { name: /developer$/ });
    expect(links.map((link) => link.textContent)).toEqual(["vue developer", "react developer"]);
    expect(within(card).getAllByText("#3")).toHaveLength(2);
    expect(within(card).getAllByRole("img", { name: /Last 4 searches/ })).toHaveLength(2);
    expect(within(card).getByText(/Stale: last attempt failed/)).toBeInTheDocument();
    expect(within(card).queryByRole("button")).not.toBeInTheDocument();
    expect(within(card).getByRole("link", { name: "Manage keywords" })).toHaveAttribute("href", "/keywords");
  });

  it("shows at most eight keywords and leaves the rest to the Keywords page", async () => {
    const many = Array.from({ length: 11 }, (_, index) => keyword({ id: index + 1, query: `keyword ${index + 1}`, activity: activity() }));
    mockApi({ ...routes(), "GET /api/v1/keywords": { body: page(many) } });
    renderApp(<OverviewView />);
    const card = (await screen.findByRole("heading", { name: "Tracked keywords" })).closest("section") as HTMLElement;

    expect(await within(card).findAllByRole("link", { name: /^keyword / })).toHaveLength(8);
  });

  it("never invents numbers when there is no data: dashes and reasons, not NaN or 0%", async () => {
    mockApi(routes({
      requests: { total: 3, by_status: { queued: 3, running: 0, succeeded: 0, failed: 0 }, by_trigger: { manual: 3, scheduled: 0 } },
      series: series({ 5: { active: 3 } }),
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
      ...routes({ series: series(), keywords: { total: 0, active: 0, scheduled: 0, stale: 0, no_data: 0 }, requests: { total: 0, by_status: { queued: 0, running: 0, succeeded: 0, failed: 0 }, by_trigger: { manual: 0, scheduled: 0 } } }),
      "GET /api/v1/keywords": { body: page([]) },
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

    expect(await screen.findByRole("alert")).toHaveTextContent(/4 queued but no worker is running/);
  });

  it("does not warn about workers when nothing is waiting", async () => {
    mockApi(routes({ queue: { queued: 0, running: 0, oldest_queued_age_seconds: null, workers_alive: 0 } }));
    renderApp(<OverviewView />);
    await screen.findByText("Success rate");

    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("flags a spent budget", async () => {
    mockApi(routes({ budget: { daily_limit: 5, used_today: 5, remaining_today: 0 } }));
    renderApp(<OverviewView />);
    await screen.findByText("Today’s budget");

    expect(within(tile("Today’s budget")).getByText(/Used up: new searches are refused until tomorrow/)).toBeInTheDocument();
  });

  it("loads the chosen period, and says which one is selected", async () => {
    const fetchMock = mockApi(routes());
    renderApp(<OverviewView />);
    await screen.findByText("Success rate");
    expect(screen.getByRole("button", { name: "24 h" })).toHaveAttribute("aria-pressed", "true");

    await userEvent.click(screen.getByRole("button", { name: "7 days" }));

    await waitFor(() => expect(fetchMock.mock.calls.some(([url]) => String(url) === "/api/v1/metrics/summary?window=7d")).toBe(true));
    expect(screen.getByRole("button", { name: "7 days" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("group", { name: "Period" })).toBeInTheDocument();
  });

  it("shows an error with a working retry when the API is down", async () => {
    let up = false;
    mockApi({
      "GET /api/v1/metrics/summary": () => (up ? { body: { data: metrics() } } : { status: 503, body: { error: { code: "http_error", message: "down" } } }),
      "GET /api/v1/keywords": { body: page([]) },
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
    expect(screen.getByText("시간대별 검색 요청")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "추적 중인 키워드" })).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent("Success rate");
  });
});
