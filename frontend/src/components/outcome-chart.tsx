"use client";

import { useId } from "react";
import type { MessageKey } from "@/lib/i18n";
import { formatNumber } from "@/lib/format";
import { buildChart, labelEvery, STACK, totalsByOutcome, type Outcome } from "@/lib/outcome-chart";
import type { Metrics } from "@/lib/types";
import { useLocale } from "./locale";

const LABEL: Record<Outcome, MessageKey> = {
  succeeded: "outcomes.succeeded", cache_hit: "outcomes.cacheHit", failed: "outcomes.failed", active: "outcomes.active",
};
const COLOR: Record<Outcome, string> = {
  succeeded: "var(--c-success)", cache_hit: "var(--c-cache)", failed: "var(--c-failed)", active: "var(--c-active)",
};
// The legend order reads from the answer you want (top of the stack) to the one you do not.
const LEGEND: Outcome[] = ["succeeded", "cache_hit", "failed", "active"];

/** Each outcome has its own pattern as well as its own colour, so the chart does not rely on colour alone. */
function Patterns({ id }: { id: string }) {
  const line = "var(--surface)";
  return (
    <defs>
      <pattern id={`${id}-succeeded`} width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
        <rect width="7" height="7" fill={COLOR.succeeded} />
        <rect width="2" height="7" fill={line} opacity="0.35" />
      </pattern>
      <pattern id={`${id}-cache_hit`} width="6" height="6" patternUnits="userSpaceOnUse">
        <rect width="6" height="6" fill={COLOR.cache_hit} />
        <circle cx="3" cy="3" r="1.1" fill={line} opacity="0.55" />
      </pattern>
      <pattern id={`${id}-failed`} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
        <rect width="6" height="6" fill={COLOR.failed} />
        <rect width="1.6" height="6" fill={line} opacity="0.5" />
        <rect width="6" height="1.6" fill={line} opacity="0.5" />
      </pattern>
      <pattern id={`${id}-active`} width="6" height="5" patternUnits="userSpaceOnUse">
        <rect width="6" height="5" fill={COLOR.active} />
        <rect width="6" height="1.5" fill={line} opacity="0.45" />
      </pattern>
    </defs>
  );
}

function sliceFormat(seconds: number): Intl.DateTimeFormatOptions {
  if (seconds >= 86_400) return { month: "numeric", day: "numeric" };
  if (seconds >= 3_600) return { month: "numeric", day: "numeric", hour: "numeric" };
  return { hour: "numeric", minute: "2-digit" };
}

/**
 * Stacked bars of the requests in each time slice, split by what happened to them. The drawing is
 * for the eyes; the same numbers are in a table for screen readers, and the legend carries totals.
 */
export function OutcomeChart({ series }: { series: Metrics["series"] }) {
  const { t, locale } = useLocale();
  const id = useId();
  const chart = buildChart(series.buckets);
  const totals = totalsByOutcome(series.buckets);
  const every = labelEvery(series.buckets.length);
  const format = new Intl.DateTimeFormat(locale, sliceFormat(series.bucket_seconds));
  const sliceLabel = (at: string) => format.format(new Date(at));
  const grandTotal = STACK.reduce((sum, outcome) => sum + totals[outcome], 0);

  if (grandTotal === 0) return <p className="rounded-xl border border-dashed border-border-strong p-8 text-center text-sm text-muted">{t("outcomes.empty")}</p>;

  return (
    <div>
      <ul className="mb-3 flex flex-wrap gap-x-5 gap-y-2 text-sm">
        {LEGEND.map((outcome) => (
          <li key={outcome} className="flex items-center gap-2">
            <svg width="14" height="14" aria-hidden="true" className="shrink-0 rounded-[3px]">
              <Patterns id={`${id}-l`} />
              <rect width="14" height="14" fill={`url(#${id}-l-${outcome})`} />
            </svg>
            <span>{t(LABEL[outcome])}</span>
            <span className="tabular-nums text-muted">{formatNumber(totals[outcome], locale)}</span>
          </li>
        ))}
      </ul>

      <div className="overflow-x-auto">
        <svg viewBox={`0 0 ${chart.layout.width} ${chart.layout.height}`} aria-hidden="true" focusable="false" className="h-auto w-full min-w-[34rem]">
          <Patterns id={id} />
          {chart.axis.ticks.map((tick) => (
            <g key={tick}>
              <line x1={chart.plot.x0} x2={chart.plot.x1} y1={chart.yFor(tick)} y2={chart.yFor(tick)} stroke="var(--border)" strokeDasharray={tick === 0 ? undefined : "3 4"} />
              <text x={chart.plot.x0 - 10} y={chart.yFor(tick) + 4} textAnchor="end" fontSize="12" fill="var(--muted)">{formatNumber(tick, locale)}</text>
            </g>
          ))}
          {chart.bars.map((bar) => (
            <g key={bar.index}>
              <title>{`${sliceLabel(bar.at)}: ${STACK.map((outcome) => `${t(LABEL[outcome])} ${series.buckets[bar.index][outcome]}`).join(", ")}`}</title>
              {bar.segments.map((segment) => (
                <rect key={segment.outcome} x={bar.x} y={segment.y} width={bar.width} height={segment.height} rx="3" fill={`url(#${id}-${segment.outcome})`} />
              ))}
              {bar.index % every === 0 && (
                <text x={bar.x + bar.width / 2} y={chart.layout.height - 8} textAnchor="middle" fontSize="12" fill="var(--muted)">{sliceLabel(bar.at)}</text>
              )}
            </g>
          ))}
        </svg>
      </div>

      {/* A table ignores the 1px width of .sr-only, so the clipping box is a div around it. */}
      <div className="sr-only">
      <table>
        <caption>{t("outcomes.tableCaption")}</caption>
        <thead>
          <tr>
            <th scope="col">{t("outcomes.slice")}</th>
            {LEGEND.map((outcome) => <th key={outcome} scope="col">{t(LABEL[outcome])}</th>)}
            <th scope="col">{t("outcomes.total")}</th>
          </tr>
        </thead>
        <tbody>
          {series.buckets.map((bucket, index) => (
            <tr key={bucket.at}>
              <th scope="row">{sliceLabel(bucket.at)}</th>
              {LEGEND.map((outcome) => <td key={outcome}>{formatNumber(bucket[outcome], locale)}</td>)}
              <td>{formatNumber(chart.bars[index].total, locale)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      </div>
    </div>
  );
}
