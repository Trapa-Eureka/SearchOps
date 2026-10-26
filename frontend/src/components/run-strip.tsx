"use client";

import type { ActivityRun } from "@/lib/types";
import { formatDateTime, formatMs } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";
import { useLocale } from "./locale";
import { cx } from "./ui";

/** How many bars the strip has. The API returns at most this many recent runs per keyword. */
export const STRIP_SLOTS = 20;

const STATUS_KEY: Record<ActivityRun["status"], MessageKey> = {
  queued: "status.queued", running: "status.running", succeeded: "status.succeeded", failed: "status.failed",
};

function kindOf(run: ActivityRun): "failed" | "cache" | "active" | "ok" {
  if (run.status === "failed") return "failed";
  if (run.status === "queued" || run.status === "running") return "active";
  return run.cache_hit ? "cache" : "ok";
}

const KIND_CLASS = { failed: "bg-c-failed", cache: "bg-c-cache", active: "bg-c-active opacity-60", ok: "bg-c-success" } as const;

/**
 * The latest searches of a keyword as small bars, oldest on the left. A bar's height is its latency
 * (a failure is full height, a cache hit or a pending search a fixed short one), so the strip shows
 * rhythm and outliers; the exact outcome is in the label, the tooltips, and the neighbouring cells.
 */
export function RunStrip({ runs }: { runs: ActivityRun[] }) {
  const { t, locale } = useLocale();
  const shown = runs.slice(-STRIP_SLOTS);
  if (shown.length === 0) return <span className="text-xs text-muted">{t("strip.none")}</span>;

  const count = (kind: ReturnType<typeof kindOf>) => shown.filter((run) => kindOf(run) === kind).length;
  const summary = t("strip.summary", { count: shown.length, succeeded: count("ok"), cache: count("cache"), failed: count("failed"), active: count("active") });
  const slowest = Math.max(0, ...shown.filter((run) => kindOf(run) === "ok").map((run) => run.latency_ms ?? 0));

  function height(run: ActivityRun): number {
    const kind = kindOf(run);
    if (kind === "failed") return 100;
    if (kind === "cache") return 38;
    if (kind === "active") return 28;
    return slowest > 0 && run.latency_ms !== null ? 30 + 70 * (run.latency_ms / slowest) : 50;
  }

  return (
    <span role="img" aria-label={summary} className="flex h-7 items-end gap-[3px]">
      {Array.from({ length: STRIP_SLOTS - shown.length }, (_, index) => (
        <span key={`empty-${index}`} aria-hidden="true" className="h-[18%] w-[5px] rounded-sm bg-border" />
      ))}
      {shown.map((run) => {
        const kind = kindOf(run);
        const title = [
          t(STATUS_KEY[run.status]),
          formatDateTime(run.created_at, locale),
          run.cache_hit ? t("run.cacheHit") : run.latency_ms !== null ? formatMs(run.latency_ms, locale) : null,
          run.retried ? t("runsTable.retries", { count: 1 }) : null,
          run.error_category,
        ].filter(Boolean).join(" · ");
        return <span key={run.id} title={title} className={cx("w-[5px] rounded-sm", KIND_CLASS[kind])} style={{ height: `${height(run)}%` }} />;
      })}
    </span>
  );
}
