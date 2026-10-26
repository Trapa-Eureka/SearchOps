import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { activityRun, renderApp } from "@/test/utils";
import type { ActivityRun } from "@/lib/types";
import { RunStrip, STRIP_SLOTS } from "./run-strip";

const runs = (items: Record<string, unknown>[]) => items.map((item, index) => activityRun({ id: index + 1, ...item })) as unknown as ActivityRun[];

describe("RunStrip", () => {
  it("says it is empty instead of drawing nothing", () => {
    renderApp(<RunStrip runs={[]} />);
    expect(screen.getByText("No searches yet")).toBeInTheDocument();
    expect(screen.queryByRole("img")).not.toBeInTheDocument();
  });

  it("describes every outcome in words, so the colours are not the only information", () => {
    renderApp(<RunStrip runs={runs([{}, {}, { status: "failed", error_category: "timeout" }, { cache_hit: true, latency_ms: null }, { status: "running", latency_ms: null }])} />);

    expect(screen.getByRole("img")).toHaveAccessibleName("Last 5 searches: 2 answered by SerpApi, 1 from cache, 1 failed, 1 queued or running.");
  });

  it("always has the same number of slots, so strips line up in a table", () => {
    const { container } = renderApp(<RunStrip runs={runs([{}, {}, {}])} />);
    expect(container.querySelectorAll("[role=img] > span")).toHaveLength(STRIP_SLOTS);
    expect(container.querySelectorAll("[role=img] > span[aria-hidden]")).toHaveLength(STRIP_SLOTS - 3);
  });

  it("shows only the newest runs when there are more than slots", () => {
    const many = runs(Array.from({ length: 30 }, () => ({})));
    const { container } = renderApp(<RunStrip runs={many} />);
    expect(container.querySelectorAll("[role=img] > span")).toHaveLength(STRIP_SLOTS);
    expect(screen.getByRole("img")).toHaveAccessibleName(/^Last 20 searches/);
  });

  it("scales a bar by latency, makes a failure full height, and keeps cache hits and pending ones short", () => {
    const { container } = renderApp(<RunStrip runs={runs([
      { latency_ms: 500 }, { latency_ms: 2000 }, { status: "failed", latency_ms: 15000, error_category: "timeout" }, { cache_hit: true, latency_ms: null }, { status: "queued", latency_ms: null },
    ])} />);
    const bars = [...container.querySelectorAll<HTMLElement>("[role=img] > span:not([aria-hidden])")];
    const heights = bars.map((bar) => parseFloat(bar.style.height));

    expect(heights[1]).toBeGreaterThan(heights[0]);
    expect(heights[1]).toBeCloseTo(100);
    expect(heights[2]).toBe(100);
    expect(heights[3]).toBeLessThan(heights[1]);
    expect(heights[4]).toBeLessThan(heights[3]);
    expect(heights.every((height) => height > 0 && height <= 100)).toBe(true);
  });

  it("has a tooltip per bar with the outcome, latency, retries and error cause", () => {
    const { container } = renderApp(<RunStrip runs={runs([{ status: "failed", latency_ms: 15000, retried: true, error_category: "timeout" }])} />);
    const bar = container.querySelector("[role=img] > span:not([aria-hidden])") as HTMLElement;
    expect(bar.title).toMatch(/^Failed · .+ · 15 s · Retried ×1 · timeout$/);
  });

  it("does not divide by zero when no run has a latency", () => {
    const { container } = renderApp(<RunStrip runs={runs([{ latency_ms: null }, { latency_ms: 0 }])} />);
    const heights = [...container.querySelectorAll<HTMLElement>("[role=img] > span:not([aria-hidden])")].map((bar) => bar.style.height);
    expect(heights.every((height) => /^\d+(\.\d+)?%$/.test(height) && !height.includes("NaN"))).toBe(true);
  });
});
