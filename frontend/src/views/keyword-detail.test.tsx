import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { formatDateTime } from "@/lib/format";
import { freshness, keyword, mockApi, options, page, renderApp, run } from "@/test/utils";
import { KeywordDetailView } from "./keyword-detail";

const push = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }), usePathname: () => "/keywords/1", useSearchParams: () => new URLSearchParams() }));

const history = (entries: unknown[]) => ({ data: entries, meta: { page: 1, per_page: 25, total_count: entries.length, total_pages: 1, freshness: freshness() } });
const entry = (id: number, day: number, rank: number | null, status = "unchanged") => ({
  id, search_run_id: id, target_domain: "react.dev", rank, found: rank !== null, captured_at: `2026-10-${day}T00:00:00Z`,
  comparison: { status, delta: status === "unchanged" ? 0 : null, previous_rank: null },
});
const detail = (overrides: Record<string, unknown> = {}) => ({
  ...run({ id: 1 }),
  results: [
    { position: 1, title: "React", url: "https://react.dev/", display_domain: "react.dev", snippet: "The library" },
    { position: 2, title: "Other", url: "https://example.com/", display_domain: "example.com", snippet: "Another" },
  ], ...overrides,
});

const routes = (over: Record<string, unknown> = {}) => ({
  "GET /api/v1/options": { body: { data: options() } },
  "GET /api/v1/keywords/1": { body: { data: keyword() } },
  "GET /api/v1/keywords/1/rank_history": { body: history([entry(2, 25, 3), entry(1, 24, 5, "baseline")]) },
  "GET /api/v1/keywords/1/searches": { body: page([run({ id: 1 })]) },
  "GET /api/v1/keywords/1/searches/1": { body: { data: detail() } },
  ...over,
});

beforeEach(() => push.mockClear());

describe("Keyword detail", () => {
  it("shows the keyword's settings, its rank history with an explicit scale, and the latest results", async () => {
    mockApi(routes());
    renderApp(<KeywordDetailView id={1} />);

    expect(await screen.findByRole("heading", { name: "react developer" })).toBeInTheDocument();
    expect(await screen.findByRole("img", { name: /Rank history chart/ })).toBeInTheDocument();
    expect(screen.getByText("Lower is better: rank 1 is the top result.")).toBeInTheDocument();
    expect(await screen.findByRole("table", { name: "Search results in order" })).toBeInTheDocument();
    expect(screen.getAllByText("Philippines · English").length).toBeGreaterThan(0);
    expect(screen.getByText("react.dev", { selector: "dd" })).toBeInTheDocument();
  });

  it("marks the target in the results and shows when the data was captured and where from", async () => {
    mockApi(routes());
    renderApp(<KeywordDetailView id={1} />);
    const results = (await screen.findByRole("table", { name: "Search results in order" })).closest("section") as HTMLElement;

    expect(within(results).getAllByText("Target domain")).toHaveLength(1);
    expect(within(results).getByText("Captured")).toBeInTheDocument();
    expect(within(results).getByText("Live SerpApi search")).toBeInTheDocument();
    expect(within(results).getByText("#3")).toBeInTheDocument();
  });

  it("is honest about a cache hit: it shows the ORIGINAL capture time and the source run", async () => {
    const hit = run({ id: 2, cache_source: "app", cache: { hit: true, source_run_id: 1, age_seconds: 7200 }, finished_at: "2026-10-26T10:00:00Z", upstream_latency_ms: null });
    mockApi(routes({
      "GET /api/v1/keywords/1/searches": { body: page([hit]) },
      "GET /api/v1/keywords/1/searches/2": { body: { data: detail({ ...hit }) } },
    }));
    renderApp(<KeywordDetailView id={1} />);

    const results = (await screen.findByRole("table", { name: "Search results in order" })).closest("section") as HTMLElement;
    expect(within(results).getByText("Cached copy of run #1")).toBeInTheDocument();
    // 10:00Z minus 2 hours = 08:00Z, not the hit's own 10:00Z (compared in whatever time zone the test runs in)
    const captured = within(results).getByText("Captured").nextElementSibling as HTMLElement;
    expect(captured.textContent).toBe(formatDateTime("2026-10-26T08:00:00Z", "en"));
    expect(captured.textContent).not.toBe(formatDateTime("2026-10-26T10:00:00Z", "en"));
  });

  it("explains an empty result instead of showing an empty table", async () => {
    mockApi(routes({
      "GET /api/v1/keywords/1/searches/1": { body: { data: detail({ results: [], empty_results: true, result_count: 0 }) } },
    }));
    renderApp(<KeywordDetailView id={1} />);

    expect(await screen.findByText("This search returned no results")).toBeInTheDocument();
    expect(screen.queryByRole("table", { name: "Search results in order" })).not.toBeInTheDocument();
  });

  it("explains when there is no history yet, and when no target domain is set", async () => {
    mockApi(routes({ "GET /api/v1/keywords/1/rank_history": { body: history([]) } }));
    const { unmount } = renderApp(<KeywordDetailView id={1} />);
    expect(await screen.findByText("No rank snapshots yet")).toBeInTheDocument();
    unmount();

    mockApi(routes({ "GET /api/v1/keywords/1": { body: { data: keyword({ target_domain: null }) } } }));
    renderApp(<KeywordDetailView id={1} />);
    expect(await screen.findByText("No target domain")).toBeInTheDocument();
  });

  it("shows a stale warning with the reason", async () => {
    mockApi(routes({ "GET /api/v1/keywords/1": { body: { data: keyword({ freshness: freshness({ state: "stale", reason: "last_attempt_failed" }) }) } } }));
    renderApp(<KeywordDetailView id={1} />);
    expect(await screen.findByText(/Stale: last attempt failed/)).toBeInTheDocument();
  });

  it("shows a missing keyword as not found, with a way back", async () => {
    mockApi({ "GET /api/v1/options": { body: { data: options() } }, "GET /api/v1/keywords/1": { status: 404, body: { error: { code: "not_found", message: "x" } } },
      "GET /api/v1/keywords/1/rank_history": { status: 404, body: { error: { code: "not_found", message: "x" } } }, "GET /api/v1/keywords/1/searches": { status: 404, body: { error: { code: "not_found", message: "x" } } } });
    renderApp(<KeywordDetailView id={1} />);

    expect(await screen.findByText(/This keyword does not exist/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /All keywords/ })).toHaveAttribute("href", "/keywords");
  });

  it("asks before deleting, and does nothing when cancelled", async () => {
    const fetchMock = mockApi(routes());
    renderApp(<KeywordDetailView id={1} />);
    await screen.findByRole("heading", { name: "react developer" });

    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    const dialog = screen.getByRole("dialog", { name: /Delete “react developer”\?/ });
    await userEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));

    expect(fetchMock.mock.calls.some(([, init]) => (init as RequestInit)?.method === "DELETE")).toBe(false);
    expect(push).not.toHaveBeenCalled();
  });

  it("deletes after confirmation and returns to the list", async () => {
    const fetchMock = mockApi(routes({ "DELETE /api/v1/keywords/1": { status: 204 }, "GET /api/v1/keywords": { body: page([]) } }));
    renderApp(<KeywordDetailView id={1} />);
    await screen.findByRole("heading", { name: "react developer" });

    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    const dialog = screen.getByRole("dialog", { name: /Delete/ });
    await userEvent.click(within(dialog).getByRole("button", { name: "Delete" }));

    await waitFor(() => expect(push).toHaveBeenCalledWith("/keywords"));
    expect(fetchMock.mock.calls.filter(([, init]) => (init as RequestInit)?.method === "DELETE")).toHaveLength(1);
  });

  it("keeps the page and reports the error when deleting fails", async () => {
    mockApi(routes({ "DELETE /api/v1/keywords/1": { status: 500, body: { error: { code: "http_error", message: "x" } } } }));
    renderApp(<KeywordDetailView id={1} />);
    await screen.findByRole("heading", { name: "react developer" });

    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    await userEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Delete" }));

    expect(await screen.findByText("The request failed (HTTP 500).")).toBeInTheDocument();
    expect(push).not.toHaveBeenCalled();
  });

  it("edits settings in place and saves them", async () => {
    const fetchMock = mockApi(routes({ "PATCH /api/v1/keywords/1": { body: { data: keyword({ target_domain: "vuejs.org" }) } } }));
    renderApp(<KeywordDetailView id={1} />);
    await screen.findByRole("heading", { name: "react developer" });

    await userEvent.click(screen.getByRole("button", { name: "Edit" }));
    const domain = await screen.findByRole("textbox", { name: /Target domain/ });
    expect(domain).toHaveValue("react.dev");
    await userEvent.clear(domain);
    await userEvent.type(domain, "vuejs.org");
    await userEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(await screen.findByText("Keyword saved.")).toBeInTheDocument();
    const patch = fetchMock.mock.calls.find(([, init]) => (init as RequestInit)?.method === "PATCH");
    expect(JSON.parse(String((patch?.[1] as RequestInit).body)).keyword).toMatchObject({ target_domain: "vuejs.org", query: "react developer" });
    await waitFor(() => expect(screen.queryByRole("textbox", { name: /Target domain/ })).not.toBeInTheDocument());
  });

  it("can force a refresh past the cache", async () => {
    const fetchMock = mockApi(routes({ "POST /api/v1/keywords/1/searches": { status: 202, body: { data: {}, meta: { outcome: "enqueued" } } } }));
    renderApp(<KeywordDetailView id={1} />);
    await screen.findByRole("heading", { name: "react developer" });

    await userEvent.click(screen.getByRole("checkbox", { name: /Skip the cache/ }));
    await userEvent.click(screen.getByRole("button", { name: "Search now" }));

    await waitFor(() => expect(fetchMock.mock.calls.some(([url, init]) => url === "/api/v1/keywords/1/searches?refresh=true" && (init as RequestInit).method === "POST")).toBe(true));
  });

  it("switches to another run's results", async () => {
    const second = run({ id: 2, rank: { target_domain: "react.dev", rank: 9, found: true } });
    mockApi(routes({
      "GET /api/v1/keywords/1/searches": { body: page([run({ id: 1 }), second]) },
      "GET /api/v1/keywords/1/searches/2": { body: { data: detail({ ...second, results: [{ position: 1, title: "Second run result", url: "https://example.org/", display_domain: "example.org", snippet: "x" }] }) } },
    }));
    renderApp(<KeywordDetailView id={1} />);
    await screen.findByRole("table", { name: "Search results in order" });

    const buttons = screen.getAllByRole("button", { name: "View results" });
    await userEvent.click(buttons[1]);

    expect(await screen.findByRole("link", { name: /Second run result/ })).toBeInTheDocument();
  });
});
