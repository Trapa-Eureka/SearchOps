// Geometry for the rank-history chart, kept free of React so it can be tested on its own.
//
// Rank 1 is at the TOP (lower is better). A snapshot where the domain was not found has no rank
// (null): it is drawn in a separate "not found" band below the scale, never as rank 0, and it
// breaks the line instead of being connected through.

export type ChartInput = { id: number; time: number; rank: number | null };
export type Layout = { width: number; height: number; left: number; right: number; top: number; bottom: number; notFoundBand: number };
export type Marker = { id: number; x: number; y: number; found: boolean; rank: number | null; time: number };
export type Chart = {
  yMax: number;
  yTicks: number[];
  markers: Marker[];
  /** Runs of consecutive found snapshots; a not-found snapshot ends a run. */
  segments: Marker[][];
  notFoundY: number | null;
  plotBottom: number;
  plot: { x0: number; x1: number; y0: number; y1: number };
};

export const DEFAULT_LAYOUT: Layout = { width: 640, height: 280, left: 44, right: 16, top: 16, bottom: 36, notFoundBand: 34 };

/** Axis maximum: at least 10, rounded up to a tidy number so ticks fall on whole ranks. */
export function niceMax(maxRank: number): number {
  if (maxRank <= 10) return 10;
  const step = maxRank <= 20 ? 5 : maxRank <= 50 ? 10 : 20;
  return Math.ceil(maxRank / step) * step;
}

export function ticksFor(yMax: number): number[] {
  const step = yMax <= 10 ? 1 : yMax <= 20 ? 5 : yMax <= 50 ? 10 : 20;
  const ticks = [1];
  for (let value = step; value <= yMax; value += step) if (value !== 1) ticks.push(value);
  return ticks;
}

export function buildChart(input: ChartInput[], layout: Layout = DEFAULT_LAYOUT): Chart {
  const points = [...input].sort((a, b) => a.time - b.time);
  const found = points.filter((point) => point.rank !== null) as (ChartInput & { rank: number })[];
  const yMax = niceMax(found.reduce((max, point) => Math.max(max, point.rank), 0));
  const hasNotFound = points.some((point) => point.rank === null);

  const x0 = layout.left;
  const x1 = layout.width - layout.right;
  const y0 = layout.top;
  const plotBottom = layout.height - layout.bottom - (hasNotFound ? layout.notFoundBand : 0);
  const notFoundY = hasNotFound ? plotBottom + layout.notFoundBand / 2 + 4 : null;

  const first = points[0]?.time ?? 0;
  const last = points[points.length - 1]?.time ?? 0;
  const xScale = (time: number) => (last === first ? (x0 + x1) / 2 : x0 + ((time - first) / (last - first)) * (x1 - x0));
  // yMax is the bottom of the rank scale; rank 1 is at y0.
  const yScale = (rank: number) => y0 + ((rank - 1) / (yMax - 1)) * (plotBottom - y0);

  const markers: Marker[] = points.map((point) => ({
    id: point.id,
    time: point.time,
    rank: point.rank,
    found: point.rank !== null,
    x: xScale(point.time),
    y: point.rank === null ? (notFoundY as number) : yScale(point.rank),
  }));

  const segments: Marker[][] = [];
  let current: Marker[] = [];
  for (const marker of markers) {
    if (marker.found) {
      current.push(marker);
    } else if (current.length > 0) {
      segments.push(current);
      current = [];
    }
  }
  if (current.length > 0) segments.push(current);

  return { yMax, yTicks: ticksFor(yMax), markers, segments, notFoundY, plotBottom, plot: { x0, x1, y0, y1: plotBottom } };
}

export function yForTick(chart: Chart, rank: number): number {
  return chart.plot.y0 + ((rank - 1) / (chart.yMax - 1)) * (chart.plot.y1 - chart.plot.y0);
}

/** "M x y L x y ..." for one segment; a single point is drawn by its marker alone. */
export function pathFor(segment: Marker[]): string {
  return segment.map((marker, index) => `${index === 0 ? "M" : "L"}${marker.x.toFixed(1)} ${marker.y.toFixed(1)}`).join(" ");
}
