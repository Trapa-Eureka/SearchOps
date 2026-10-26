import type { SeriesBucket } from "./types";

/** Segments are stacked from the bottom up in this order, so failures sit on the baseline. */
export const STACK = ["failed", "active", "cache_hit", "succeeded"] as const;
export type Outcome = (typeof STACK)[number];

export type ChartLayout = { width: number; height: number; left: number; right: number; top: number; bottom: number };
export const DEFAULT_LAYOUT: ChartLayout = { width: 900, height: 280, left: 44, right: 8, top: 12, bottom: 30 };

const STEPS = [1, 2, 5];
const MIN_TOP_TICKS = 4;
const MAX_TICKS = 5;

/** A tidy step for the axis so that at most MAX_TICKS steps cover the maximum. */
export function axisStep(max: number): number {
  for (let power = 1; ; power *= 10) {
    for (const base of STEPS) {
      const step = base * power;
      if (max / step <= MAX_TICKS) return step;
    }
  }
}

/** The axis: 0 up to a round maximum, with at least MIN_TOP_TICKS steps so a small count does not fill the chart. */
export function axisFor(max: number): { top: number; ticks: number[] } {
  const small = Math.max(max, 0);
  const step = small <= MIN_TOP_TICKS ? 1 : axisStep(small);
  const count = Math.max(MIN_TOP_TICKS, Math.ceil(small / step));
  return { top: step * count, ticks: Array.from({ length: count + 1 }, (_, index) => index * step) };
}

export type Segment = { outcome: Outcome; value: number; y: number; height: number };
export type Bar = { index: number; at: string; x: number; width: number; total: number; segments: Segment[] };
export type ChartGeometry = {
  layout: ChartLayout;
  plot: { x0: number; x1: number; y0: number; y1: number };
  axis: { top: number; ticks: number[] };
  yFor: (value: number) => number;
  bars: Bar[];
};

const GAP = 2;
const MIN_SEGMENT = 3;

export function buildChart(buckets: SeriesBucket[], layout: ChartLayout = DEFAULT_LAYOUT): ChartGeometry {
  const plot = { x0: layout.left, x1: layout.width - layout.right, y0: layout.top, y1: layout.height - layout.bottom };
  const totals = buckets.map((bucket) => STACK.reduce((sum, outcome) => sum + bucket[outcome], 0));
  const axis = axisFor(Math.max(0, ...totals));
  const yFor = (value: number) => plot.y1 - (value / axis.top) * (plot.y1 - plot.y0);

  const band = buckets.length === 0 ? 0 : (plot.x1 - plot.x0) / buckets.length;
  const width = Math.min(band * 0.62, 34);

  const bars = buckets.map((bucket, index): Bar => {
    const x = plot.x0 + band * index + (band - width) / 2;
    let cursor = plot.y1;
    const segments: Segment[] = [];
    for (const outcome of STACK) {
      const value = bucket[outcome];
      if (value <= 0) continue;
      // Even a single request stays visible: a segment is never thinner than MIN_SEGMENT.
      const height = Math.max(MIN_SEGMENT, plot.y1 - yFor(value) - (segments.length > 0 ? GAP : 0));
      segments.push({ outcome, value, y: cursor - height, height });
      cursor -= height + GAP;
    }
    return { index, at: bucket.at, x, width, total: totals[index], segments };
  });

  return { layout, plot, axis, yFor, bars };
}

/** Which bars get an x-axis label, so that labels never overlap: about eight across. */
export function labelEvery(count: number): number {
  return Math.max(1, Math.ceil(count / 8));
}

export function totalsByOutcome(buckets: SeriesBucket[]): Record<Outcome, number> {
  return Object.fromEntries(STACK.map((outcome) => [outcome, buckets.reduce((sum, bucket) => sum + bucket[outcome], 0)])) as Record<Outcome, number>;
}
