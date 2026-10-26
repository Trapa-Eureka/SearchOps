import { screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { renderApp } from "@/test/utils";
import type { RankHistoryEntry } from "@/lib/types";
import { RankChart } from "./rank-chart";

const entry = (id: number, day: number, rank: number | null): RankHistoryEntry => ({
  id, search_run_id: id, target_domain: "react.dev", rank, found: rank !== null,
  captured_at: new Date(Date.UTC(2026, 9, day)).toISOString(), comparison: { status: "unchanged", delta: 0, previous_rank: rank },
});

// newest first, as the API returns it
const entries = [entry(4, 25, 3), entry(3, 24, null), entry(2, 23, 5), entry(1, 22, 9)];

describe("RankChart", () => {
  it("is an image with a title and a summary of the latest rank, for screen readers", () => {
    renderApp(<RankChart entries={entries} targetDomain="react.dev" />);
    const chart = screen.getByRole("img", { name: /Rank history chart/ });
    expect(chart).toHaveAccessibleDescription(/react\.dev is at rank 3 in the latest of 4 snapshots\. Lower is better/);
  });

  it("states that lower is better, in text", () => {
    renderApp(<RankChart entries={entries} targetDomain="react.dev" />);
    expect(screen.getByText("Lower is better: rank 1 is the top result.")).toBeInTheDocument();
  });

  it("explains that a cross is 'not found', not rank 0", () => {
    renderApp(<RankChart entries={entries} targetDomain="react.dev" />);
    expect(screen.getByText(/not in the retrieved results\. It is not rank 0/)).toBeInTheDocument();
  });

  it("draws one marker per snapshot, with a text alternative for each", () => {
    renderApp(<RankChart entries={entries} targetDomain="react.dev" />);
    const svg = screen.getByRole("img");
    expect(within(svg).getAllByText(/^Rank \d+ on /)).toHaveLength(3);
    expect(within(svg).getAllByText(/^Not found on /)).toHaveLength(1);
  });

  it("labels the not-found band only when something was not found", () => {
    const { rerender } = renderApp(<RankChart entries={entries} targetDomain="react.dev" />);
    expect(within(screen.getByRole("img")).getByText("Not found")).toBeInTheDocument();
    rerender(<RankChart entries={[entry(2, 23, 5), entry(1, 22, 9)]} targetDomain="react.dev" />);
    expect(within(screen.getByRole("img")).queryByText("Not found")).not.toBeInTheDocument();
  });

  it("summarises a latest snapshot that was not found as such", () => {
    renderApp(<RankChart entries={[entry(2, 24, null), entry(1, 23, 4)]} targetDomain="react.dev" />);
    expect(screen.getByRole("img")).toHaveAccessibleDescription(/react\.dev was not found in the latest of 2 snapshots/);
  });

  it("works with a single snapshot", () => {
    renderApp(<RankChart entries={[entry(1, 23, 4)]} targetDomain="react.dev" />);
    expect(within(screen.getByRole("img")).getAllByText(/^Rank 4 on /)).toHaveLength(1);
  });

  it("is translated", () => {
    renderApp(<RankChart entries={entries} targetDomain="react.dev" />, { locale: "ko" });
    expect(screen.getByText("숫자가 작을수록 좋습니다: 1위가 맨 위입니다.")).toBeInTheDocument();
  });
});
