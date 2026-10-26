"use client";

import type { Run, RunStatus } from "@/lib/types";
import { formatDateTime, formatMs } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";
import { useLocale } from "./locale";
import { cx } from "./ui";

const BLOCK: Record<RunStatus, { icon: string; className: string; key: MessageKey }> = {
  succeeded: { icon: "✓", className: "bg-ok-bg text-ok border-ok", key: "status.succeeded" },
  failed: { icon: "✕", className: "bg-danger-bg text-danger border-danger", key: "status.failed" },
  running: { icon: "↻", className: "bg-info-bg text-info border-info", key: "status.running" },
  queued: { icon: "…", className: "bg-bg text-muted border-border", key: "status.queued" },
};

/** The most recent runs, oldest on the left. Each block has a symbol as well as a colour, and a text label. */
export function RunTimeline({ runs }: { runs: Run[] }) {
  const { t, locale } = useLocale();
  const chronological = [...runs].reverse();
  return (
    <ol aria-label={t("timeline.label")} className="flex flex-wrap gap-1">
      {chronological.map((run) => {
        const block = BLOCK[run.status];
        const description = [
          t(block.key),
          run.keyword?.query,
          formatDateTime(run.created_at, locale),
          run.cache.hit ? t("run.cacheHit") : formatMs(run.upstream_latency_ms, locale),
          run.attempts > 1 ? t("runsTable.retries", { count: run.attempts - 1 }) : null,
          run.error_category,
        ].filter(Boolean).join(" · ");
        return (
          <li key={run.id} title={description} className={cx("relative flex size-7 items-center justify-center rounded border text-xs font-bold", block.className)}>
            <span aria-hidden="true">{run.cache.hit ? "⚡" : block.icon}</span>
            {run.attempts > 1 && <span aria-hidden="true" className="absolute -right-1 -top-1 size-2.5 rounded-full border border-surface bg-warn" />}
            <span className="sr-only">{description}</span>
          </li>
        );
      })}
    </ol>
  );
}
