import { describe, expect, it } from "vitest";
import { buildChart, DEFAULT_LAYOUT, niceMax, pathFor, ticksFor, yForTick } from "./rank-chart";

const DAY = 86_400_000;
const point = (id: number, day: number, rank: number | null) => ({ id, time: day * DAY, rank });

describe("axis", () => {
  it("is at least 10 and rounds up to a tidy number", () => {
    expect(niceMax(0)).toBe(10);
    expect(niceMax(3)).toBe(10);
    expect(niceMax(10)).toBe(10);
    expect(niceMax(11)).toBe(15);
    expect(niceMax(20)).toBe(20);
    expect(niceMax(21)).toBe(30);
    expect(niceMax(51)).toBe(60);
    expect(niceMax(100)).toBe(100);
  });

  it("always includes rank 1 and ends at the axis maximum", () => {
    for (const max of [10, 15, 20, 30, 60, 100]) {
      const ticks = ticksFor(max);
      expect(ticks[0]).toBe(1);
      expect(ticks.at(-1)).toBeGreaterThanOrEqual(max - 20);
      expect(new Set(ticks).size).toBe(ticks.length);
    }
  });
});

describe("rank 1 is at the top (lower is better)", () => {
  it("puts a better rank above a worse one", () => {
    const chart = buildChart([point(1, 0, 8), point(2, 1, 2)]);
    const [worse, better] = chart.markers;
    expect(better.y).toBeLessThan(worse.y);
  });

  it("places rank 1 on the first grid line and the axis maximum on the last", () => {
    const chart = buildChart([point(1, 0, 1), point(2, 1, 10)]);
    expect(chart.markers[0].y).toBeCloseTo(chart.plot.y0);
    expect(chart.markers[1].y).toBeCloseTo(chart.plot.y1);
    expect(yForTick(chart, 1)).toBeCloseTo(chart.plot.y0);
    expect(yForTick(chart, chart.yMax)).toBeCloseTo(chart.plot.y1);
  });

  it("keeps every rank inside the plot area", () => {
    const chart = buildChart([point(1, 0, 1), point(2, 1, 37), point(3, 2, 5)]);
    for (const marker of chart.markers) {
      expect(marker.y).toBeGreaterThanOrEqual(chart.plot.y0 - 0.001);
      expect(marker.y).toBeLessThanOrEqual(chart.plot.y1 + 0.001);
    }
  });
});

describe("not found", () => {
  it("is drawn in its own band below the scale, never as rank 0", () => {
    const chart = buildChart([point(1, 0, 3), point(2, 1, null), point(3, 2, 4)]);
    const missing = chart.markers[1];
    expect(missing.found).toBe(false);
    expect(missing.rank).toBeNull();
    expect(chart.notFoundY).not.toBeNull();
    expect(missing.y).toBeGreaterThan(chart.plot.y1);
    expect(missing.y).toBeGreaterThan(Math.max(...chart.markers.filter((m) => m.found).map((m) => m.y)));
  });

  it("breaks the line instead of connecting across it", () => {
    const chart = buildChart([point(1, 0, 5), point(2, 1, 4), point(3, 2, null), point(4, 3, 3), point(5, 4, 3)]);
    expect(chart.segments.map((segment) => segment.map((m) => m.id))).toEqual([[1, 2], [4, 5]]);
  });

  it("reserves the band only when something was not found", () => {
    expect(buildChart([point(1, 0, 3), point(2, 1, 2)]).notFoundY).toBeNull();
    const without = buildChart([point(1, 0, 3)]);
    const withBand = buildChart([point(1, 0, 3), point(2, 1, null)]);
    expect(withBand.plot.y1).toBeLessThan(without.plot.y1);
  });

  it("handles a history that was never found", () => {
    const chart = buildChart([point(1, 0, null), point(2, 1, null)]);
    expect(chart.segments).toEqual([]);
    expect(chart.yMax).toBe(10);
    expect(chart.markers.every((marker) => !marker.found)).toBe(true);
  });

  it("starts a new segment after a gap even for a single found point", () => {
    const chart = buildChart([point(1, 0, 3), point(2, 1, null), point(3, 2, 2)]);
    expect(chart.segments).toHaveLength(2);
    expect(pathFor(chart.segments[1])).toMatch(/^M[\d.]+ [\d.]+$/);
  });
});

describe("time axis", () => {
  it("spaces points by real time, not by count", () => {
    const chart = buildChart([point(1, 0, 5), point(2, 1, 5), point(3, 10, 5)]);
    const [a, b, c] = chart.markers.map((marker) => marker.x);
    expect((b - a) / (c - a)).toBeCloseTo(0.1, 5);
    expect(a).toBeCloseTo(chart.plot.x0);
    expect(c).toBeCloseTo(chart.plot.x1);
  });

  it("sorts points that arrive newest first", () => {
    const chart = buildChart([point(3, 2, 1), point(2, 1, 2), point(1, 0, 3)]);
    expect(chart.markers.map((marker) => marker.id)).toEqual([1, 2, 3]);
    expect(chart.markers[0].x).toBeLessThan(chart.markers[2].x);
  });

  it("centres a single point and points that share a moment", () => {
    const mid = (DEFAULT_LAYOUT.left + DEFAULT_LAYOUT.width - DEFAULT_LAYOUT.right) / 2;
    expect(buildChart([point(1, 0, 4)]).markers[0].x).toBeCloseTo(mid);
    const same = buildChart([point(1, 5, 4), point(2, 5, 6)]);
    expect(same.markers.map((marker) => marker.x)).toEqual([mid, mid]);
  });

  it("copes with no points at all", () => {
    const chart = buildChart([]);
    expect(chart.markers).toEqual([]);
    expect(chart.segments).toEqual([]);
    expect(Number.isFinite(chart.plot.x0)).toBe(true);
  });
});

describe("pathFor", () => {
  it("joins points with a move then lines, rounded to one decimal", () => {
    expect(pathFor([
      { id: 1, x: 10.04, y: 20.06, found: true, rank: 1, time: 0 },
      { id: 2, x: 30, y: 40, found: true, rank: 2, time: 1 },
    ])).toBe("M10.0 20.1 L30.0 40.0");
  });
});
