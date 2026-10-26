import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { renderApp, run } from "@/test/utils";
import type { RankHistoryEntry, Run, SearchResultRow } from "@/lib/types";
import { RankTable, ResultsTable, RunsTable } from "./tables";

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
