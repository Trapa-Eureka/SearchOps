"use client";

import Link from "next/link";
import { useState } from "react";
import { FreshnessBadge } from "@/components/badges";
import { useLocale } from "@/components/locale";
import { RunsTable } from "@/components/tables";
import { Button, Card, EmptyState, ErrorState, Loading, Metric, PageTitle, INPUT_CLASS } from "@/components/ui";
import { useKeywords, useMetrics, useRecentRuns } from "@/hooks/api";
import { formatMs, formatNumber, formatPercent } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";

const WINDOWS = ["1h", "24h", "7d", "30d"] as const;
const WINDOW_KEY: Record<(typeof WINDOWS)[number], MessageKey> = { "1h": "window.1h", "24h": "window.24h", "7d": "window.7d", "30d": "window.30d" };

export function OverviewView() {
  const { t, locale } = useLocale();
  const [windowName, setWindowName] = useState<(typeof WINDOWS)[number]>("24h");
  const metrics = useMetrics(windowName);
  const keywords = useKeywords(1, 100);
  const recent = useRecentRuns({ per_page: 8 });

  const stale = (keywords.data?.data ?? []).filter((keyword) => keyword.freshness?.state === "stale");
  const data = metrics.data?.data;

  return (
    <>
      <PageTitle title={t("overview.title")}>
        <label className="flex items-center gap-2">
          {t("window.label")}
          <select className={`${INPUT_CLASS} w-auto py-1`} value={windowName} onChange={(event) => setWindowName(event.target.value as (typeof WINDOWS)[number])}>
            {WINDOWS.map((name) => <option key={name} value={name}>{t(WINDOW_KEY[name])}</option>)}
          </select>
        </label>
      </PageTitle>

      {metrics.error && <ErrorState error={metrics.error} onRetry={() => metrics.mutate()} />}
      {!data && !metrics.error && <Loading />}

      {data && data.keywords.total === 0 && data.requests.total === 0 && (
        <EmptyState
          title={t("overview.emptyTitle")}
          action={<div className="flex flex-wrap justify-center gap-2"><Link href="/keywords"><Button variant="primary">{t("overview.addKeyword")}</Button></Link><Link href="/planner"><Button>{t("overview.tryPlanner")}</Button></Link></div>}
        >
          {t("overview.emptyBody")}
        </EmptyState>
      )}

      {data && (data.keywords.total > 0 || data.requests.total > 0) && (
        <>
          <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Metric label={t("metric.keywords")} value={`${formatNumber(data.keywords.active, locale)} / ${formatNumber(data.keywords.total, locale)}`}
              hint={data.keywords.stale > 0 ? t("metric.keywordsStale", { count: data.keywords.stale }) : t("metric.keywordsHint", { scheduled: data.keywords.scheduled })} tone={data.keywords.stale > 0 ? "warn" : "neutral"} />
            <Metric label={t("metric.successRate")} value={formatPercent(data.upstream.success_rate, locale)}
              hint={data.upstream.success_rate === null ? t("metric.noFinished") : t("metric.successHint", { ok: data.upstream.runs_succeeded, failed: data.upstream.runs_failed })} />
            <Metric label={t("metric.latencyP50")} value={formatMs(data.upstream.latency_ms.p50, locale)} hint={t("metric.samples", { count: data.upstream.latency_ms.samples })} />
            <Metric label={t("metric.latencyP95")} value={formatMs(data.upstream.latency_ms.p95, locale)} hint={t("metric.latencyMax", { max: formatMs(data.upstream.latency_ms.max, locale) })} />
            <Metric label={t("metric.upstreamCalls")} value={formatNumber(data.upstream.calls, locale)} hint={t("metric.retriesHint", { count: data.upstream.retries })} />
            <Metric label={t("metric.cacheHitRate")} value={formatPercent(data.cache.hit_rate, locale)}
              hint={data.cache.hit_rate === null ? t("metric.noRequests") : t("metric.cacheHint", { hits: data.cache.hits, misses: data.cache.misses, seconds: data.cache.ttl_seconds })} />
            <Metric label={t("metric.budget")} value={`${formatNumber(data.budget.used_today, locale)} / ${formatNumber(data.budget.daily_limit, locale)}`}
              hint={data.budget.remaining_today === 0 ? t("metric.budgetSpent") : t("metric.budgetLeft", { count: data.budget.remaining_today })} tone={data.budget.remaining_today === 0 ? "danger" : "neutral"} />
            <Metric label={t("metric.workers")} value={formatNumber(data.queue.workers_alive, locale)}
              hint={data.queue.workers_alive === 0 && data.queue.queued > 0 ? t("metric.noWorkerWarning", { count: data.queue.queued }) : t("metric.queueHint", { queued: data.queue.queued, running: data.queue.running })}
              tone={data.queue.workers_alive === 0 && data.queue.queued > 0 ? "danger" : "neutral"} />
          </dl>

          <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]">
            <Card title={t("overview.attention")}>
              {keywords.error && <ErrorState error={keywords.error} onRetry={() => keywords.mutate()} />}
              {!keywords.data && !keywords.error && <Loading />}
              {keywords.data && stale.length === 0 && <p className="text-sm text-muted">{t("overview.nothingStale")}</p>}
              {stale.length > 0 && (
                <ul className="divide-y divide-border">
                  {stale.map((keyword) => (
                    <li key={keyword.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                      <Link href={`/keywords/${keyword.id}`} className="font-medium text-accent underline-offset-2 hover:underline">{keyword.query}</Link>
                      <FreshnessBadge freshness={keyword.freshness} withTime />
                    </li>
                  ))}
                </ul>
              )}
            </Card>

            <Card title={t("overview.recent")} actions={<Link href="/health" className="text-sm text-accent underline-offset-2 hover:underline">{t("overview.allActivity")}</Link>}>
              {recent.error && <ErrorState error={recent.error} onRetry={() => recent.mutate()} />}
              {!recent.data && !recent.error && <Loading />}
              {recent.data && recent.data.data.length === 0 && <p className="text-sm text-muted">{t("overview.noRuns")}</p>}
              {recent.data && recent.data.data.length > 0 && <RunsTable runs={recent.data.data} showKeyword />}
            </Card>
          </div>
        </>
      )}
    </>
  );
}
