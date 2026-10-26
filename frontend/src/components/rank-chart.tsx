"use client";

import { useId } from "react";
import { buildChart, DEFAULT_LAYOUT, pathFor, yForTick } from "@/lib/rank-chart";
import { formatDateTime } from "@/lib/format";
import type { RankHistoryEntry } from "@/lib/types";
import { useLocale, useT } from "./locale";

/**
 * Rank over time, with rank 1 at the top. A snapshot where the domain was not found sits in its
 * own "not found" band and breaks the line: it is not rank 0 and not "last place". The same data
 * is available as a table below the chart, which is also the accessible alternative.
 */
export function RankChart({ entries, targetDomain }: { entries: RankHistoryEntry[]; targetDomain: string | null }) {
  const t = useT();
  const { locale } = useLocale();
  const titleId = useId();
  const descId = useId();
  const layout = DEFAULT_LAYOUT;

  const chart = buildChart(entries.map((entry) => ({ id: entry.id, time: Date.parse(entry.captured_at), rank: entry.rank })), layout);
  const newest = entries[0];
  const firstTime = chart.markers[0]?.time;
  const lastTime = chart.markers[chart.markers.length - 1]?.time;

  const summary = newest
    ? newest.rank === null
      ? t("chart.summaryNotFound", { domain: targetDomain ?? "", count: entries.length })
      : t("chart.summaryRank", { domain: targetDomain ?? "", rank: newest.rank, count: entries.length })
    : "";

  return (
    <figure>
      <svg viewBox={`0 0 ${layout.width} ${layout.height}`} role="img" aria-labelledby={titleId} aria-describedby={descId} className="h-auto w-full">
        <title id={titleId}>{t("chart.title")}</title>
        <desc id={descId}>{summary} {t("chart.lowerIsBetter")}</desc>

        {chart.yTicks.map((tick) => (
          <g key={tick}>
            <line x1={chart.plot.x0} x2={chart.plot.x1} y1={yForTick(chart, tick)} y2={yForTick(chart, tick)} stroke="var(--border)" strokeWidth={1} />
            <text x={chart.plot.x0 - 8} y={yForTick(chart, tick) + 4} textAnchor="end" fontSize={11} fill="var(--muted)">{tick}</text>
          </g>
        ))}
        <text x={12} y={layout.top + 6} fontSize={11} fill="var(--muted)" transform={`rotate(-90 12 ${layout.top + 6})`} textAnchor="end">{t("chart.axisRank")}</text>

        {chart.notFoundY !== null && (
          <g>
            <rect x={chart.plot.x0} y={chart.plotBottom + 6} width={chart.plot.x1 - chart.plot.x0} height={layout.notFoundBand} fill="var(--warn-bg)" rx={4} />
            <text x={chart.plot.x0 + 6} y={chart.plotBottom + 18} fontSize={10} fill="var(--warn)">{t("chart.notFoundBand")}</text>
          </g>
        )}

        {chart.segments.map((segment) => (
          <path key={segment[0]?.id} d={pathFor(segment)} fill="none" stroke="var(--accent)" strokeWidth={2} strokeLinejoin="round" />
        ))}

        {chart.markers.map((marker, index) =>
          marker.found ? (
            <circle key={marker.id} cx={marker.x} cy={marker.y} r={index === chart.markers.length - 1 ? 6 : 4} fill="var(--accent)" stroke="var(--surface)" strokeWidth={2}>
              <title>{t("chart.pointFound", { rank: marker.rank ?? 0, when: formatDateTime(new Date(marker.time).toISOString(), locale) })}</title>
            </circle>
          ) : (
            <g key={marker.id} stroke="var(--warn)" strokeWidth={2.5} strokeLinecap="round">
              <title>{t("chart.pointNotFound", { when: formatDateTime(new Date(marker.time).toISOString(), locale) })}</title>
              <line x1={marker.x - 5} y1={marker.y - 5} x2={marker.x + 5} y2={marker.y + 5} />
              <line x1={marker.x - 5} y1={marker.y + 5} x2={marker.x + 5} y2={marker.y - 5} />
            </g>
          ),
        )}

        {firstTime !== undefined && (
          <text x={chart.plot.x0} y={layout.height - 8} fontSize={11} fill="var(--muted)" textAnchor="start">{formatDateTime(new Date(firstTime).toISOString(), locale)}</text>
        )}
        {lastTime !== undefined && lastTime !== firstTime && (
          <text x={chart.plot.x1} y={layout.height - 8} fontSize={11} fill="var(--muted)" textAnchor="end">{formatDateTime(new Date(lastTime).toISOString(), locale)}</text>
        )}
      </svg>
      <figcaption className="mt-2 space-y-1 text-xs text-muted">
        <p className="font-medium text-text">{t("chart.lowerIsBetter")}</p>
        <p>{t("chart.legendNotFound")}</p>
        <p>{t("chart.scopeNote")}</p>
      </figcaption>
    </figure>
  );
}
