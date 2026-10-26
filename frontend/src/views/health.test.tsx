import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { freshness, keyword, metrics, mockApi, page, renderApp, run } from "@/test/utils";
import { HealthView } from "./health";

const where = { id: 1, query: "react developer", country: "ph", language: "en", target_domain: "react.dev" };
const runs = [
  run({ id: 4, status: "failed", error_category: "timeout", error_message: "timed out", attempts: 3, keyword: where }),
  run({ id: 3, status: "succeeded", cache_source: "app", cache: { hit: true, source_run_id: 1, age_seconds: 5 }, keyword: where }),
  run({ id: 2, status: "succeeded", keyword: where }),
];
const routes = (over: Record<string, unknown> = {}) => ({
  "GET /api/v1/metrics/summary": { body: { data: metrics() } },
  "GET /api/v1/searches": { body: page(runs) },
  "GET /api/v1/keywords": { body: page([keyword(), keyword({ id: 2, query: "vue developer", freshness: freshness({ state: "stale", reason: "overdue" }) })]) },
  ...over,
});

describe("API health", () => {
  it("shows reliability numbers, the error causes, and retries", async () => {
    mockApi(routes());
    renderApp(<HealthView />);
    await screen.findByText("Success rate");

    const tile = (label: string) => screen.getByText(label, { selector: "dt span" }).closest("div") as HTMLElement;
    expect(within(tile("Retries")).getByText("1")).toBeInTheDocument();
    expect(within(tile("Retries")).getByText("9 requests sent to SerpApi")).toBeInTheDocument();

    const errors = screen.getByRole("table", { name: "Failures by cause" });
    expect(within(errors).getByText("Timed out")).toBeInTheDocument();
    expect(within(errors).getByText("Invalid or missing API key")).toBeInTheDocument();
  });

  it("draws a timeline whose every block has text, not just a colour", async () => {
    mockApi(routes());
    renderApp(<HealthView />);
    const timeline = await screen.findByRole("list", { name: "Most recent searches, oldest first" });

    const blocks = within(timeline).getAllByRole("listitem");
    expect(blocks).toHaveLength(3);
    expect(blocks[0]).toHaveTextContent(/Succeeded/);
    expect(blocks[1]).toHaveTextContent(/Cache hit/);
    expect(blocks[2]).toHaveTextContent(/Failed.*Retried ×2.*timeout/);
  });

  it("lists stale keywords", async () => {
    mockApi(routes());
    renderApp(<HealthView />);
    const section = (await screen.findByRole("heading", { name: "Stale data" })).closest("section") as HTMLElement;
    expect(await within(section).findByRole("link", { name: "vue developer" })).toBeInTheDocument();
    expect(within(section).getByText(/Stale: overdue/)).toBeInTheDocument();
  });

  it("says plainly when there were no errors", async () => {
    mockApi(routes({ "GET /api/v1/metrics/summary": { body: { data: metrics({ errors: {} }) } } }));
    renderApp(<HealthView />);
    expect(await screen.findByText("No failures in this period.")).toBeInTheDocument();
  });

  it("warns when searches wait and no worker is alive", async () => {
    mockApi(routes({ "GET /api/v1/metrics/summary": { body: { data: metrics({ queue: { queued: 2, running: 0, oldest_queued_age_seconds: 120, workers_alive: 0 } }) } } }));
    renderApp(<HealthView />);
    await screen.findByText("Workers running");
    const tile = screen.getByText("Workers running", { selector: "dt span" }).closest("div") as HTMLElement;
    expect(within(tile).getByText(/2 queued but no worker is running/)).toBeInTheDocument();
    const oldest = screen.getByText("Oldest queued search", { selector: "dt span" }).closest("div") as HTMLElement;
    expect(within(oldest).getByText("120 s")).toBeInTheDocument();
  });

  it("describes the Laya state without implying it ran when it did not", async () => {
    mockApi(routes());
    const { unmount } = renderApp(<HealthView />);
    expect(await screen.findByText("No planning requests in this period.")).toBeInTheDocument();
    unmount();

    mockApi(routes({ "GET /api/v1/metrics/summary": { body: { data: metrics({ intent: { enabled: false, requests: 0, by_outcome: {}, fallbacks: {}, laya_latency_ms: { samples: 0, p50: null, p95: null, max: null } } }) } } }));
    renderApp(<HealthView />);
    expect(await screen.findByText("Off")).toBeInTheDocument();
  });

  it("filters the run list by status and starts again at page 1", async () => {
    const fetchMock = mockApi(routes());
    renderApp(<HealthView />);
    await screen.findAllByRole("table");

    await userEvent.click(screen.getByRole("button", { name: /^Failed/ }));

    await waitFor(() => expect(fetchMock.mock.calls.some(([url]) => String(url).includes("status=failed") && String(url).includes("per_page=10"))).toBe(true));
  });

  it("shows how many searches each status has on its tab, for all searches rather than the period", async () => {
    mockApi(routes({ "GET /api/v1/searches": { body: { data: runs, meta: { page: 1, per_page: 10, total_count: 3, total_pages: 1, counts: { all: 393, queued: 0, running: 0, succeeded: 372, failed: 21 } } } } }));
    renderApp(<HealthView />);

    expect(await screen.findByRole("button", { name: "All 393" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "Failed 21" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Succeeded 372" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Queued 0" })).toBeInTheDocument();
    expect(screen.getByText(/counts on the tabs cover every search, not only the selected period/)).toBeInTheDocument();
  });

  it("explains an empty log", async () => {
    mockApi(routes({ "GET /api/v1/searches": { body: page([]) } }));
    renderApp(<HealthView />);
    expect(await screen.findByText("No searches yet")).toBeInTheDocument();
  });

  it("keeps showing the log when the metrics fail, and offers a retry for the metrics", async () => {
    mockApi(routes({ "GET /api/v1/metrics/summary": { status: 500, body: { error: { code: "http_error", message: "x" } } } }));
    renderApp(<HealthView />);

    const alert = await screen.findByRole("alert");
    expect(within(alert).getByRole("button", { name: "Try again" })).toBeInTheDocument();
    expect((await screen.findAllByRole("table")).length).toBeGreaterThan(0);
  });
});
