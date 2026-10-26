"use client";

import Link from "next/link";
import { useState } from "react";
import { useLocale } from "@/components/locale";
import { OutcomeChart } from "@/components/outcome-chart";
import { KeywordsTable } from "@/components/tables";
import { Button, Card, EmptyState, ErrorState, Loading, Metric, PageTitle, Segmented } from "@/components/ui";
import { useKeywords, useMetrics } from "@/hooks/api";
import { formatMs, formatNumber, formatPercent } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";

const WINDOWS = ["1h", "24h", "7d", "30d"] as const;
type WindowName = (typeof WINDOWS)[number];
const WINDOW_KEY: Record<WindowName, MessageKey> = { "1h": "window.s1h", "24h": "window.s24h", "7d": "window.s7d", "30d": "window.s30d" };
/** How many keywords the overview lists; the Keywords page has the rest. */
const SHOWN = 8;

export function OverviewView() {
  const { t, locale } = useLocale();
  const [windowName, setWindowName] = useState<WindowName>("24h");
  const metrics = useMetrics(windowName);
  const keywords = useKeywords(1, 100);
  const data = metrics.data?.data;

  // Keywords with stale data first: they are the ones that need a look.
  const ordered = [...(keywords.data?.data ?? [])].sort((a, b) => Number(b.freshness?.state === "stale") - Number(a.freshness?.state === "stale"));
  const noWorker = data !== undefined && data.queue.workers_alive === 0 && data.queue.queued > 0;

  return (
    <>
      <PageTitle title={t("overview.title")} description={t("overview.description")}>
        <Segmented
          label={t("window.label")}
          value={windowName}
          onChange={setWindowName}
          options={WINDOWS.map((name) => ({ value: name, label: t(WINDOW_KEY[name]) }))}
        />
      </PageTitle>

      {metrics.error && <ErrorState error={metrics.error} onRetry={() => metrics.mutate()} />}
      {!data && !metrics.error && <Loading />}

      {data && data.keywords.total === 0 && data.requests.total === 0 && (
        <EmptyState
          title={t("overview.emptyTitle")}
          action={<div className="flex flex-wrap justify-center gap-2"><Link href="/keywords"><Button variant="primary" icon="plus">{t("overview.addKeyword")}</Button></Link><Link href="/planner"><Button icon="sparkle">{t("overview.tryPlanner")}</Button></Link></div>}
        >
          {t("overview.emptyBody")}
        </EmptyState>
      )}

      {data && (data.keywords.total > 0 || data.requests.total > 0) && (
        <div className="grid gap-5">
          {noWorker && (
            <p role="alert" className="rounded-xl border border-danger bg-danger-bg p-3 text-sm font-medium text-danger">
              {t("metric.noWorkerWarning", { count: data.queue.queued })}
            </p>
          )}

          <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <Metric icon="check" iconTone="ok" label={t("metric.successRate")} value={formatPercent(data.upstream.success_rate, locale)}
              hint={data.upstream.success_rate === null ? t("metric.noFinished") : t("metric.successHint", { ok: data.upstream.runs_succeeded, failed: data.upstream.runs_failed })} />
            <Metric icon="gauge" label={t("metric.latencyP50")} value={formatMs(data.upstream.latency_ms.p50, locale)}
              hint={`${t("metric.latencyP95")} ${formatMs(data.upstream.latency_ms.p95, locale)} · ${t("metric.latencyMax", { max: formatMs(data.upstream.latency_ms.max, locale) })}`} />
            <Metric icon="bolt" label={t("metric.cacheHitRate")} value={formatPercent(data.cache.hit_rate, locale)}
              hint={data.cache.hit_rate === null ? t("metric.noRequests") : t("metric.cacheHint", { hits: data.cache.hits, misses: data.cache.misses, seconds: data.cache.ttl_seconds })} />
            <Metric icon="coins" iconTone={data.budget.remaining_today === 0 ? "danger" : "warn"} label={t("metric.budget")} value={`${formatNumber(data.budget.used_today, locale)} / ${formatNumber(data.budget.daily_limit, locale)}`}
              hint={data.budget.remaining_today === 0 ? t("metric.budgetSpent") : t("metric.budgetLeft", { count: data.budget.remaining_today })} tone={data.budget.remaining_today === 0 ? "danger" : "neutral"} />
          </dl>

          <Card icon="pulse" title={t("outcomes.title")} description={t("outcomes.description")}
            actions={<Link href="/health" className="text-sm font-medium text-accent underline-offset-2 hover:underline">{t("overview.allActivity")}</Link>}>
            <OutcomeChart series={data.series} />
          </Card>
        </div>
      )}

      {data && (data.keywords.total > 0 || data.requests.total > 0) && (
        <Card icon="search" title={t("overview.keywords")} description={t("overview.keywordsDescription")} className="mt-5"
          actions={<Link href="/keywords" className="text-sm font-medium text-accent underline-offset-2 hover:underline">{t("overview.viewAll")}</Link>}>
          {keywords.error && <ErrorState error={keywords.error} onRetry={() => keywords.mutate()} />}
          {!keywords.data && !keywords.error && <Loading />}
          {keywords.data && ordered.length === 0 && <p className="text-sm text-muted">{t("keywords.emptyTitle")}</p>}
          {ordered.length > 0 && <KeywordsTable keywords={ordered.slice(0, SHOWN)} />}
        </Card>
      )}
    </>
  );
}
