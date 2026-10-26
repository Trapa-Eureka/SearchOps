import { describe, expect, it } from "vitest";
import { axisFor, axisStep, buildChart, labelEvery, STACK, totalsByOutcome } from "./outcome-chart";
import type { SeriesBucket } from "./types";

const bucket = (index: number, parts: Partial<Record<(typeof STACK)[number], number>> = {}): SeriesBucket => ({
  at: new Date(Date.UTC(2026, 9, 26, index)).toISOString(), succeeded: 0, cache_hit: 0, failed: 0, active: 0, ...parts,
});

describe("axis", () => {
  it("picks a tidy step so that at most five steps cover the maximum", () => {
    expect(axisStep(5)).toBe(1);
    expect(axisStep(6)).toBe(2);
    expect(axisStep(10)).toBe(2);
    expect(axisStep(11)).toBe(5);
    expect(axisStep(25)).toBe(5);
    expect(axisStep(26)).toBe(10);
    expect(axisStep(120)).toBe(50);
    expect(axisStep(1000)).toBe(200);
  });

  it("never draws fewer than four steps, so a tiny count does not fill the chart", () => {
    expect(axisFor(0)).toEqual({ top: 4, ticks: [0, 1, 2, 3, 4] });
    expect(axisFor(1)).toEqual({ top: 4, ticks: [0, 1, 2, 3, 4] });
    expect(axisFor(4).top).toBe(4);
  });

  it("always reaches the maximum and starts at zero", () => {
    for (const max of [5, 7, 13, 29, 64, 100, 333, 1200]) {
      const { top, ticks } = axisFor(max);
      expect(top).toBeGreaterThanOrEqual(max);
      expect(ticks[0]).toBe(0);
      expect(ticks.at(-1)).toBe(top);
      expect(ticks.length).toBeLessThanOrEqual(7);
    }
  });

  it("treats a negative maximum as zero", () => {
    expect(axisFor(-3).top).toBe(4);
  });
});

describe("buildChart", () => {
  it("makes one bar per slice, in order, evenly spaced inside the plot", () => {
    const chart = buildChart([bucket(0), bucket(1), bucket(2)]);
    expect(chart.bars.map((bar) => bar.index)).toEqual([0, 1, 2]);
    const xs = chart.bars.map((bar) => bar.x);
    expect(xs[1] - xs[0]).toBeCloseTo(xs[2] - xs[1]);
    expect(xs[0]).toBeGreaterThanOrEqual(chart.plot.x0);
    expect(xs[2] + chart.bars[2].width).toBeLessThanOrEqual(chart.plot.x1);
  });

  it("stacks failures on the baseline, then queued, cache hits, and answered requests on top", () => {
    const chart = buildChart([bucket(0, { succeeded: 4, cache_hit: 3, failed: 2, active: 1 })]);
    const segments = chart.bars[0].segments;

    expect(segments.map((segment) => segment.outcome)).toEqual(["failed", "active", "cache_hit", "succeeded"]);
    for (let index = 1; index < segments.length; index += 1) {
      expect(segments[index].y).toBeLessThan(segments[index - 1].y);
    }
    expect(segments[0].y + segments[0].height).toBeCloseTo(chart.plot.y1);
    expect(chart.bars[0].total).toBe(10);
  });

  it("scales heights to the values: twice the requests is about twice as tall", () => {
    const chart = buildChart([bucket(0, { succeeded: 10 }), bucket(1, { succeeded: 20 })]);
    const [small, large] = chart.bars.map((bar) => bar.segments[0].height);
    expect(large / small).toBeCloseTo(2, 0);
  });

  it("keeps the tallest bar inside the plot", () => {
    const chart = buildChart([bucket(0, { succeeded: 37, failed: 5 }), bucket(1, { cache_hit: 9 })]);
    for (const bar of chart.bars) {
      for (const segment of bar.segments) {
        expect(segment.y).toBeGreaterThanOrEqual(chart.plot.y0 - 0.001);
        expect(segment.y + segment.height).toBeLessThanOrEqual(chart.plot.y1 + 0.001);
      }
    }
  });

  it("keeps a single request visible even when the axis is large", () => {
    const chart = buildChart([bucket(0, { succeeded: 1000 }), bucket(1, { failed: 1 })]);
    expect(chart.bars[1].segments[0].height).toBeGreaterThanOrEqual(3);
  });

  it("draws nothing for a quiet slice, and its total is zero", () => {
    const chart = buildChart([bucket(0), bucket(1, { succeeded: 2 })]);
    expect(chart.bars[0].segments).toEqual([]);
    expect(chart.bars[0].total).toBe(0);
  });

  it("copes with no slices and with all-zero slices", () => {
    expect(buildChart([]).bars).toEqual([]);
    const flat = buildChart([bucket(0), bucket(1)]);
    expect(flat.axis.top).toBe(4);
    expect(flat.bars.every((bar) => bar.segments.length === 0)).toBe(true);
  });

  it("caps the bar width so a short window does not give huge bars", () => {
    expect(buildChart([bucket(0), bucket(1)]).bars[0].width).toBeLessThanOrEqual(34);
  });

  it("yFor maps zero to the baseline and the axis maximum to the top", () => {
    const chart = buildChart([bucket(0, { succeeded: 8 })]);
    expect(chart.yFor(0)).toBeCloseTo(chart.plot.y1);
    expect(chart.yFor(chart.axis.top)).toBeCloseTo(chart.plot.y0);
  });
});

describe("labels and totals", () => {
  it("shows about eight labels however many bars there are", () => {
    expect(labelEvery(12)).toBe(2);
    expect(labelEvery(24)).toBe(3);
    expect(labelEvery(14)).toBe(2);
    expect(labelEvery(30)).toBe(4);
    expect(labelEvery(5)).toBe(1);
    expect(labelEvery(0)).toBe(1);
  });

  it("sums each outcome over the period, so the legend adds up to every request", () => {
    const totals = totalsByOutcome([bucket(0, { succeeded: 2, failed: 1 }), bucket(1, { succeeded: 3, cache_hit: 4, active: 1 })]);
    expect(totals).toEqual({ succeeded: 5, cache_hit: 4, failed: 1, active: 1 });
  });
});
