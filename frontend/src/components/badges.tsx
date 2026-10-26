"use client";

import type { ComparisonStatus, Freshness, Run, RunStatus } from "@/lib/types";
import { formatRelative } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";
import { useLocale, useT } from "./locale";
import type { IconName } from "./icons";
import { Icon } from "./icons";
import { Badge, cx, type Tone } from "./ui";

const STATUS: Record<RunStatus, { tone: Tone; icon: IconName; key: MessageKey }> = {
  queued: { tone: "neutral", icon: "clock", key: "status.queued" },
  running: { tone: "info", icon: "refresh", key: "status.running" },
  succeeded: { tone: "ok", icon: "check", key: "status.succeeded" },
  failed: { tone: "danger", icon: "cross", key: "status.failed" },
};

export function RunStatusBadge({ status }: { status: RunStatus }) {
  const t = useT();
  const { tone, icon, key } = STATUS[status];
  return <Badge tone={tone} icon={icon}>{t(key)}</Badge>;
}

export function CacheBadge({ run }: { run: Pick<Run, "cache"> }) {
  const t = useT();
  if (!run.cache.hit) return null;
  return <Badge tone="info" icon="bolt" title={t("run.cacheHitHint")}>{t("run.cacheHit")}</Badge>;
}

export function TriggerBadge({ trigger }: { trigger: Run["triggered_by"] }) {
  const t = useT();
  return <Badge>{trigger === "scheduled" ? t("run.trigger.scheduled") : t("run.trigger.manual")}</Badge>;
}

export function FreshnessBadge({ freshness, withTime = false }: { freshness: Freshness | undefined; withTime?: boolean }) {
  const t = useT();
  const { locale } = useLocale();
  if (!freshness) return null;

  const when = freshness.last_success_at ? formatRelative(freshness.last_success_at, locale) : null;
  if (freshness.state === "no_data") return <Badge tone="neutral" icon="circle">{t("freshness.noData")}</Badge>;
  if (freshness.state === "stale") {
    const reason = freshness.reason === "overdue" ? t("freshness.overdue") : t("freshness.lastFailed");
    return (
      <span className="inline-flex flex-wrap items-center gap-1.5">
        <Badge tone="warn" icon="warning" title={reason}>{t("freshness.stale")}: {reason}</Badge>
        {withTime && when && <span className="text-xs text-muted">{t("freshness.lastGood", { when })}</span>}
      </span>
    );
  }
  return (
    <span className="inline-flex flex-wrap items-center gap-1.5">
      <Badge tone="ok" icon="check">{t("freshness.fresh")}</Badge>
      {withTime && when && <span className="text-xs text-muted">{when}</span>}
    </span>
  );
}

const CHANGE: Record<ComparisonStatus, { tone: Tone; icon: IconName; key: MessageKey }> = {
  improved: { tone: "ok", icon: "up", key: "change.improved" },
  declined: { tone: "danger", icon: "down", key: "change.declined" },
  unchanged: { tone: "neutral", icon: "flat", key: "change.unchanged" },
  entered: { tone: "ok", icon: "plus", key: "change.entered" },
  dropped: { tone: "danger", icon: "down", key: "change.dropped" },
  not_found: { tone: "neutral", icon: "cross", key: "change.notFound" },
  not_comparable: { tone: "warn", icon: "warning", key: "change.notComparable" },
  baseline: { tone: "info", icon: "diamond", key: "change.baseline" },
};

/** How a rank moved. Smaller rank is better, so "improved" means the number went down. */
export function ChangeBadge({ status, delta }: { status: ComparisonStatus; delta: number | null }) {
  const t = useT();
  const { tone, icon, key } = CHANGE[status];
  const amount = delta !== null && delta !== 0 ? ` ${delta > 0 ? "+" : "−"}${Math.abs(delta)}` : "";
  return <Badge tone={tone} icon={icon} title={status === "not_comparable" ? t("change.notComparableHint") : undefined}>{t(key)}{amount}</Badge>;
}

/** A rank, or an explicit "not found". A missing rank is never shown as 0. */
export function RankValue({ rank }: { rank: number | null }) {
  const t = useT();
  if (rank === null) return <span className="text-muted" title={t("rank.notFoundHint")}>{t("rank.notFound")}</span>;
  return <span className="font-semibold tabular-nums">#{rank}</span>;
}

const CHANGE_TEXT: Partial<Record<ComparisonStatus, string>> = { improved: "text-ok", declined: "text-danger" };

/**
 * A compact rank movement for tables: an arrow and how many places. Smaller rank is better, so
 * "improved" points up. Cases without a number (first snapshot, dropped out, not comparable) say so in words.
 */
export function RankChange({ comparison }: { comparison: { status: ComparisonStatus; delta: number | null } }) {
  const t = useT();
  const { status, delta } = comparison;
  const label = t(CHANGE[status].key);
  if (delta !== null && delta !== 0) {
    return (
      <span className={cx("inline-flex items-center gap-0.5 text-xs font-medium", CHANGE_TEXT[status])} title={label}>
        <Icon name={delta > 0 ? "up" : "down"} className="size-3.5" />
        {Math.abs(delta)}
        <span className="sr-only"> {label}</span>
      </span>
    );
  }
  return <span className="whitespace-nowrap text-xs text-muted">{label}</span>;
}
