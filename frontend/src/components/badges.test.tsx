import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { renderApp, freshness } from "@/test/utils";
import { CacheBadge, ChangeBadge, FreshnessBadge, RankChange, RankValue, RunStatusBadge, TriggerBadge } from "./badges";
import type { Freshness, RunStatus } from "@/lib/types";

describe("RunStatusBadge", () => {
  it.each([["queued", "Queued"], ["running", "Running"], ["succeeded", "Succeeded"], ["failed", "Failed"]] as [RunStatus, string][])(
    "says %s in words, not only with a colour", (status, label) => {
      renderApp(<RunStatusBadge status={status} />);
      expect(screen.getByText(label)).toBeInTheDocument();
    },
  );

  it("is translated", () => {
    renderApp(<RunStatusBadge status="failed" />, { locale: "ko" });
    expect(screen.getByText("실패")).toBeInTheDocument();
  });
});

describe("CacheBadge / TriggerBadge", () => {
  it("only shows for a cache hit", () => {
    const { rerender } = renderApp(<CacheBadge run={{ cache: { hit: false, source_run_id: null, age_seconds: null } }} />);
    expect(screen.queryByText("Cache hit")).not.toBeInTheDocument();
    rerender(<CacheBadge run={{ cache: { hit: true, source_run_id: 3, age_seconds: 10 } }} />);
    expect(screen.getByText("Cache hit")).toBeInTheDocument();
  });

  it("labels who started a run", () => {
    renderApp(<><TriggerBadge trigger="scheduled" /><TriggerBadge trigger="manual" /></>);
    expect(screen.getByText("Scheduled")).toBeInTheDocument();
    expect(screen.getByText("Manual")).toBeInTheDocument();
  });
});

describe("FreshnessBadge", () => {
  const fresh = freshness() as Freshness;

  it("renders nothing without data", () => {
    const { container } = renderApp(<FreshnessBadge freshness={undefined} />);
    expect(container.textContent).toBe("");
  });

  it("shows no data, fresh, and stale as different words", () => {
    const { rerender } = renderApp(<FreshnessBadge freshness={freshness({ state: "no_data", last_success_at: null }) as Freshness} />);
    expect(screen.getByText("No data yet")).toBeInTheDocument();
    rerender(<FreshnessBadge freshness={fresh} />);
    expect(screen.getByText("Fresh")).toBeInTheDocument();
    rerender(<FreshnessBadge freshness={freshness({ state: "stale", reason: "last_attempt_failed" }) as Freshness} />);
    expect(screen.getByText(/Stale: last attempt failed/)).toBeInTheDocument();
  });

  it("explains an overdue scheduled keyword differently", () => {
    renderApp(<FreshnessBadge freshness={freshness({ state: "stale", reason: "overdue" }) as Freshness} />);
    expect(screen.getByText(/Stale: overdue/)).toBeInTheDocument();
  });

  it("says when the last good result was, so a stale rank is not mistaken for current", () => {
    renderApp(<FreshnessBadge withTime freshness={freshness({ state: "stale", reason: "last_attempt_failed", last_success_at: new Date(Date.now() - 5 * 3_600_000).toISOString() }) as Freshness} />);
    expect(screen.getByText(/last good result 5 hours ago/)).toBeInTheDocument();
  });
});

describe("ChangeBadge", () => {
  it("shows the direction and the size of a move", () => {
    const { rerender } = renderApp(<ChangeBadge status="improved" delta={3} />);
    expect(screen.getByText("Improved +3")).toBeInTheDocument();
    rerender(<ChangeBadge status="declined" delta={-2} />);
    expect(screen.getByText("Declined −2")).toBeInTheDocument();
    rerender(<ChangeBadge status="unchanged" delta={0} />);
    expect(screen.getByText("Unchanged")).toBeInTheDocument();
  });

  it("names each non-numeric status", () => {
    const { rerender } = renderApp(<ChangeBadge status="entered" delta={null} />);
    expect(screen.getByText("Now found")).toBeInTheDocument();
    rerender(<ChangeBadge status="dropped" delta={null} />);
    expect(screen.getByText("Dropped out")).toBeInTheDocument();
    rerender(<ChangeBadge status="baseline" delta={null} />);
    expect(screen.getByText("First snapshot")).toBeInTheDocument();
    rerender(<ChangeBadge status="not_comparable" delta={null} />);
    expect(screen.getByText("Not comparable")).toHaveAttribute("title", expect.stringMatching(/cannot be compared/));
  });
});

describe("RankValue", () => {
  it("shows a rank with a hash", () => {
    renderApp(<RankValue rank={3} />);
    expect(screen.getByText("#3")).toBeInTheDocument();
  });

  it("shows an explicit 'not found', never #0 or a blank", () => {
    renderApp(<RankValue rank={null} />);
    expect(screen.getByText("Not found")).toBeInTheDocument();
    expect(screen.queryByText(/#0/)).not.toBeInTheDocument();
  });
});

describe("RankChange", () => {
  it("shows an arrow and how many places, with the word for screen readers", () => {
    const { rerender } = renderApp(<RankChange comparison={{ status: "improved", delta: 3 }} />);
    expect(screen.getByText("3").closest("span")).toHaveTextContent("3 Improved");
    expect(screen.getByTitle("Improved")).toBeInTheDocument();

    rerender(<RankChange comparison={{ status: "declined", delta: -2 }} />);
    expect(screen.getByText("2").closest("span")).toHaveTextContent("2 Declined");
  });

  it("uses words when there is no number to show", () => {
    const { rerender } = renderApp(<RankChange comparison={{ status: "unchanged", delta: 0 }} />);
    expect(screen.getByText("Unchanged")).toBeInTheDocument();
    rerender(<RankChange comparison={{ status: "baseline", delta: null }} />);
    expect(screen.getByText("First snapshot")).toBeInTheDocument();
    rerender(<RankChange comparison={{ status: "not_comparable", delta: null }} />);
    expect(screen.getByText("Not comparable")).toBeInTheDocument();
    rerender(<RankChange comparison={{ status: "dropped", delta: null }} />);
    expect(screen.getByText("Dropped out")).toBeInTheDocument();
  });
});
