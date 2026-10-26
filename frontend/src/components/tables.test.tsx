import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { activity, freshness, keyword, renderApp, run } from "@/test/utils";
import type { Keyword, RankHistoryEntry, Run, SearchResultRow } from "@/lib/types";
import { KeywordsTable, RankTable, ResultsTable, RunsTable } from "./tables";

const result = (position: number, url: string, extra: Partial<SearchResultRow> = {}): SearchResultRow => ({
  position, url, title: `Title ${position}`, display_domain: null, snippet: `Snippet ${position}`, ...extra,
});

describe("ResultsTable", () => {
  const results = [
    result(1, "https://en.wikipedia.org/wiki/React", { display_domain: "en.wikipedia.org" }),
    result(2, "https://www.react.dev/learn", { display_domain: "react.dev" }),
    result(3, "https://notreact.dev/", { display_domain: "notreact.dev" }),
    result(4, "https://blog.react.dev/post", { display_domain: "blog.react.dev" }),
  ];

  it("lists results in order with their domains and snippets", () => {
    renderApp(<ResultsTable results={results} targetDomain="react.dev" />);
    const rows = screen.getAllByRole("row").slice(1);
    expect(rows).toHaveLength(4);
    expect(within(rows[0]).getByText("#1")).toBeInTheDocument();
    expect(within(rows[0]).getByText("Snippet 1")).toBeInTheDocument();
  });

  it("marks the target and its subdomains, but not a look-alike domain", () => {
    renderApp(<ResultsTable results={results} targetDomain="react.dev" />);
    const rows = screen.getAllByRole("row").slice(1);
    expect(within(rows[1]).getByText("Target domain")).toBeInTheDocument();
    expect(within(rows[3]).getByText("Target domain")).toBeInTheDocument();
    expect(within(rows[2]).queryByText("Target domain")).not.toBeInTheDocument();
    expect(within(rows[0]).queryByText("Target domain")).not.toBeInTheDocument();
  });

  it("marks nothing when no domain is tracked", () => {
    renderApp(<ResultsTable results={results} targetDomain={null} />);
    expect(screen.queryByText("Target domain")).not.toBeInTheDocument();
  });

  it("opens links safely in a new tab and tells screen readers so", () => {
    renderApp(<ResultsTable results={results} targetDomain={null} />);
    const link = screen.getByRole("link", { name: /Title 2/ });
    expect(link).toHaveAttribute("href", "https://www.react.dev/learn");
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(link).toHaveAccessibleName(/opens in a new tab/);
  });

  it("never turns a javascript: URL into a link", () => {
    renderApp(<ResultsTable results={[result(1, "javascript:alert(1)")]} targetDomain={null} />);
    expect(screen.queryByRole("link")).not.toBeInTheDocument();
    expect(screen.getByText("Title 1")).toBeInTheDocument();
  });

  it("falls back to the URL when there is no title", () => {
    renderApp(<ResultsTable results={[result(1, "https://example.com/x", { title: null })]} targetDomain={null} />);
    expect(screen.getByRole("link", { name: /https:\/\/example\.com\/x/ })).toBeInTheDocument();
  });

  it("is a table with a caption and column headers", () => {
    renderApp(<ResultsTable results={results} targetDomain={null} />);
    expect(screen.getByRole("table", { name: "Search results in order" })).toBeInTheDocument();
    expect(screen.getAllByRole("columnheader").map((header) => header.textContent)).toEqual(["Position", "Result", "Domain"]);
  });
});

describe("RankTable", () => {
  const entries: RankHistoryEntry[] = [
    { id: 2, search_run_id: 2, target_domain: "react.dev", rank: null, found: false, captured_at: "2026-10-25T00:00:00Z", comparison: { status: "dropped", delta: null, previous_rank: 4 } },
    { id: 1, search_run_id: 1, target_domain: "react.dev", rank: 4, found: true, captured_at: "2026-10-24T00:00:00Z", comparison: { status: "baseline", delta: null, previous_rank: null } },
  ];

  it("shows 'Not found' for a missing rank and never #0", () => {
    renderApp(<RankTable entries={entries} />);
    const rows = screen.getAllByRole("row").slice(1);
    expect(within(rows[0]).getByText("Not found")).toBeInTheDocument();
    expect(within(rows[0]).getByText("Dropped out")).toBeInTheDocument();
    expect(within(rows[0]).getByText("#4")).toBeInTheDocument();
    expect(screen.queryByText("#0")).not.toBeInTheDocument();
  });

  it("shows the previous rank, or a dash for the first snapshot", () => {
    renderApp(<RankTable entries={entries} />);
    const rows = screen.getAllByRole("row").slice(1);
    expect(within(rows[1]).getByText("First snapshot")).toBeInTheDocument();
    expect(within(rows[1]).getByText("—")).toBeInTheDocument();
  });
});

describe("RunsTable", () => {
  const runs = [
    run({ id: 4, status: "failed", error_category: "timeout", error_message: "SerpApi request timed out", attempts: 3, upstream_latency_ms: 15000, http_status: null }),
    run({ id: 3, status: "succeeded", cache: { hit: true, source_run_id: 1, age_seconds: 20 }, cache_source: "app", upstream_latency_ms: null, attempts: 0 }),
    run({ id: 2, status: "succeeded", attempts: 2, triggered_by: "scheduled" }),
    run({ id: 1, status: "succeeded", empty_results: true, result_count: 0 }),
    run({ id: 5, status: "queued", attempts: 0, upstream_latency_ms: null }),
  ] as unknown as Run[];

  it("explains a failure by its cause, with the message as a tooltip", () => {
    renderApp(<RunsTable runs={runs} />);
    const cause = screen.getByText("Timed out");
    expect(cause).toHaveAttribute("title", "SerpApi request timed out");
  });

  it("flags retried runs and shows latency", () => {
    renderApp(<RunsTable runs={runs} />);
    expect(screen.getAllByText(/Retried ×/)).toHaveLength(2);
    expect(screen.getByText("Retried ×2")).toBeInTheDocument();
    expect(screen.getByText("15 s")).toBeInTheDocument();
  });

  it("shows a cache hit without a latency", () => {
    renderApp(<RunsTable runs={runs} />);
    const row = screen.getByText("Cache hit").closest("tr") as HTMLElement;
    expect(within(row).getByText("—", { selector: "td" })).toBeInTheDocument();
  });

  it("distinguishes an empty result from a result count", () => {
    renderApp(<RunsTable runs={runs} />);
    expect(screen.getByText("Empty result")).toBeInTheDocument();
    expect(screen.getAllByText("6 results").length).toBeGreaterThan(0);
  });

  it("lets only succeeded runs be opened", async () => {
    const onSelect = vi.fn();
    renderApp(<RunsTable runs={runs} onSelect={onSelect} selectedId={2} />);
    const buttons = screen.getAllByRole("button", { name: "View results" });
    expect(buttons).toHaveLength(5);
    expect(buttons.filter((button) => (button as HTMLButtonElement).disabled)).toHaveLength(2); // failed and queued
    const selected = buttons.find((button) => button.getAttribute("aria-pressed") === "true");
    expect(selected).toBeDefined();
    const openable = buttons.find((button) => !(button as HTMLButtonElement).disabled && button !== selected) as HTMLElement;
    await userEvent.click(openable);
    expect(onSelect).toHaveBeenCalledTimes(1);
  });

  it("shows the keyword column and links to it when asked", () => {
    renderApp(<RunsTable showKeyword runs={[run({ id: 9, keyword: { id: 7, query: "vue developer", country: "us", language: "en", target_domain: null } }) as unknown as Run]} />);
    expect(screen.getByRole("link", { name: "vue developer" })).toHaveAttribute("href", "/keywords/7");
  });
});

describe("KeywordsTable", () => {
  const rows = [
    keyword({ id: 1, query: "react developer" }),
    keyword({ id: 2, query: "vue developer", target_domain: "vuejs.org", activity: activity({ rank: { rank: null, found: false, captured_at: "2026-10-26T00:00:00Z", target_domain: "vuejs.org", comparison: { status: "dropped", delta: null, previous_rank: 4 } } }) }),
    keyword({ id: 3, query: "python tutorial", target_domain: null, active: false, schedule: "weekly", activity: activity({ rank: null, recent_runs: [], latency_ms: { samples: 0, p95: null, max: null } }), freshness: freshness({ state: "no_data", last_success_at: null }) }),
    keyword({ id: 4, query: "new one", activity: undefined }),
  ] as unknown as Keyword[];
  const noop = () => undefined;

  it("shows the rank with how far it moved, and the target domain under it", () => {
    renderApp(<KeywordsTable keywords={rows} onSearch={noop} onToggleActive={noop} />);
    const row = screen.getByRole("link", { name: "react developer" }).closest("tr") as HTMLElement;

    expect(within(row).getByText("#3")).toBeInTheDocument();
    expect(within(row).getByText("react.dev")).toBeInTheDocument();
    expect(within(row).getByText(/Improved/)).toBeInTheDocument(); // read by screen readers; the arrow shows 2 places
  });

  it("says 'Not found' without a number for a keyword that dropped out, never rank 0", () => {
    renderApp(<KeywordsTable keywords={rows} onSearch={noop} onToggleActive={noop} />);
    const row = screen.getByRole("link", { name: "vue developer" }).closest("tr") as HTMLElement;

    expect(within(row).getByText("Not found")).toBeInTheDocument();
    expect(within(row).getByText("Dropped out")).toBeInTheDocument();
    expect(within(row).queryByText("#0")).not.toBeInTheDocument();
  });

  it("shows dashes and reasons, not made-up values, when there is no rank, no runs, or no activity at all", () => {
    renderApp(<KeywordsTable keywords={rows} onSearch={noop} onToggleActive={noop} />);

    const python = screen.getByRole("link", { name: "python tutorial" }).closest("tr") as HTMLElement;
    expect(within(python).getByText("none")).toBeInTheDocument();
    expect(within(python).getByText("No searches yet")).toBeInTheDocument();
    expect(within(python).getByText("Paused")).toBeInTheDocument();
    expect(within(python).getByText("No data yet")).toBeInTheDocument();

    const fresh = screen.getByRole("link", { name: "new one" }).closest("tr") as HTMLElement;
    expect(within(fresh).getAllByText("—").length).toBeGreaterThanOrEqual(2);
    expect(document.body).not.toHaveTextContent("NaN");
  });

  it("shows p95 with a tooltip saying what it covers", () => {
    renderApp(<KeywordsTable keywords={rows} onSearch={noop} onToggleActive={noop} />);
    const row = screen.getByRole("link", { name: "react developer" }).closest("tr") as HTMLElement;

    expect(within(row).getByText("14 s")).toHaveAttribute("title", "Slowest 5% of the last 3 searches that called SerpApi");
  });

  it("gives the action buttons words for screen readers and tooltips for the mouse", () => {
    renderApp(<KeywordsTable keywords={rows} onSearch={noop} onToggleActive={noop} />);
    const row = screen.getByRole("link", { name: "react developer" }).closest("tr") as HTMLElement;

    expect(within(row).getByRole("button", { name: "Search now" })).toHaveAttribute("title", "Search now");
    expect(within(row).getByRole("button", { name: "Pause" })).toBeInTheDocument();
    expect(within(screen.getByRole("link", { name: "python tutorial" }).closest("tr") as HTMLElement).getByRole("button", { name: "Resume" })).toBeInTheDocument();
  });

  it("is read-only without handlers: no actions column", () => {
    renderApp(<KeywordsTable keywords={rows} />);

    expect(screen.queryByRole("button")).not.toBeInTheDocument();
    expect(screen.getAllByRole("columnheader")).toHaveLength(5);
  });

  it("starts the avatar with the first letter, also for Korean and emoji", () => {
    const odd = [keyword({ id: 9, query: "react 개발자" }), keyword({ id: 10, query: "개발자 react" }), keyword({ id: 11, query: "🚀 launch" })] as unknown as Keyword[];
    renderApp(<KeywordsTable keywords={odd} />);

    expect(screen.getAllByText(/^(R|개|🚀)$/).map((node) => node.textContent)).toEqual(["R", "개", "🚀"]);
  });
});
