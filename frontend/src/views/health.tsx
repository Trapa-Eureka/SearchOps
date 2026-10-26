"use client";

import Link from "next/link";
import { useState } from "react";
import { FreshnessBadge } from "@/components/badges";
import { useLocale } from "@/components/locale";
import { errorCategoryLabel, RunsTable } from "@/components/tables";
import { RunTimeline } from "@/components/timeline";
import { Badge, Card, EmptyState, ErrorState, INPUT_CLASS, Loading, Metric, PageTitle, Pagination } from "@/components/ui";
import { useKeywords, useMetrics, useRecentRuns } from "@/hooks/api";
import { formatMs, formatNumber, formatPercent, formatRelative } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";

const WINDOWS = ["1h", "24h", "7d", "30d"] as const;
const WINDOW_KEY: Record<(typeof WINDOWS)[number], MessageKey> = { "1h": "window.1h", "24h": "window.24h", "7d": "window.7d", "30d": "window.30d" };
const STATUS_FILTERS = ["", "failed", "succeeded", "running", "queued"] as const;
const FILTER_KEY: Record<(typeof STATUS_FILTERS)[number], MessageKey> = {
  "": "health.filterAll", failed: "status.failed", succeeded: "status.succeeded", running: "status.running", queued: "status.queued",
};

export function HealthView() {
  const { t, locale } = useLocale();
  const [windowName, setWindowName] = useState<(typeof WINDOWS)[number]>("24h");
  const [status, setStatus] = useState<(typeof STATUS_FILTERS)[number]>("");
  const [page, setPage] = useState(1);

  const metrics = useMetrics(windowName);
  const timeline = useRecentRuns({ per_page: 50 });
  const runs = useRecentRuns({ per_page: 10, page, status });
  const keywords = useKeywords(1, 100);

  const data = metrics.data?.data;
  const stale = (keywords.data?.data ?? []).filter((keyword) => keyword.freshness?.state === "stale");
  const errors = Object.entries(data?.errors ?? {}).sort((a, b) => b[1] - a[1]);
  const failedTotal = errors.reduce((sum, [, count]) => sum + count, 0);

  return (
    <>
      <PageTitle title={t("health.title")}>
        <label className="flex items-center gap-2">
          {t("window.label")}
          <select className={`${INPUT_CLASS} w-auto py-1`} value={windowName} onChange={(event) => setWindowName(event.target.value as (typeof WINDOWS)[number])}>
            {WINDOWS.map((name) => <option key={name} value={name}>{t(WINDOW_KEY[name])}</option>)}
          </select>
        </label>
      </PageTitle>

      {metrics.error && <ErrorState error={metrics.error} onRetry={() => metrics.mutate()} />}
      {!data && !metrics.error && <Loading />}

      {data && (
        <>
          <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Metric label={t("metric.successRate")} value={formatPercent(data.upstream.success_rate, locale)} hint={data.upstream.success_rate === null ? t("metric.noFinished") : t("metric.successHint", { ok: data.upstream.runs_succeeded, failed: data.upstream.runs_failed })} />
            <Metric label={t("metric.latencyP50")} value={formatMs(data.upstream.latency_ms.p50, locale)} hint={t("metric.samples", { count: data.upstream.latency_ms.samples })} />
            <Metric label={t("metric.latencyP95")} value={formatMs(data.upstream.latency_ms.p95, locale)} hint={t("metric.latencyMax", { max: formatMs(data.upstream.latency_ms.max, locale) })} />
            <Metric label={t("metric.retries")} value={formatNumber(data.upstream.retries, locale)} hint={t("metric.upstreamCallsHint", { count: data.upstream.calls })} tone={data.upstream.retries > 0 ? "warn" : "neutral"} />
            <Metric label={t("metric.cacheHitRate")} value={formatPercent(data.cache.hit_rate, locale)} hint={data.cache.hit_rate === null ? t("metric.noRequests") : t("metric.cacheHint", { hits: data.cache.hits, misses: data.cache.misses, seconds: data.cache.ttl_seconds })} />
            <Metric label={t("metric.budget")} value={`${formatNumber(data.budget.used_today, locale)} / ${formatNumber(data.budget.daily_limit, locale)}`} hint={data.budget.remaining_today === 0 ? t("metric.budgetSpent") : t("metric.budgetLeft", { count: data.budget.remaining_today })} tone={data.budget.remaining_today === 0 ? "danger" : "neutral"} />
            <Metric label={t("metric.workers")} value={formatNumber(data.queue.workers_alive, locale)}
              hint={data.queue.workers_alive === 0 && data.queue.queued > 0 ? t("metric.noWorkerWarning", { count: data.queue.queued }) : t("metric.queueHint", { queued: data.queue.queued, running: data.queue.running })}
              tone={data.queue.workers_alive === 0 && data.queue.queued > 0 ? "danger" : "neutral"} />
            <Metric label={t("metric.oldestQueued")} value={data.queue.oldest_queued_age_seconds === null ? "—" : formatMs(data.queue.oldest_queued_age_seconds * 1000, locale)} hint={data.queue.oldest_queued_age_seconds === null ? t("metric.nothingQueued") : t("metric.waitingForWorker")} />
          </dl>

          <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-2">
            <Card title={t("health.errors")}>
              {errors.length === 0
                ? <p className="text-sm text-muted">{t("health.noErrors")}</p>
                : (
                  <table className="w-full text-sm">
                    <caption className="sr-only">{t("health.errors")}</caption>
                    <thead><tr><th scope="col" className="pb-2 text-left text-xs font-medium uppercase text-muted">{t("health.category")}</th><th scope="col" className="pb-2 text-right text-xs font-medium uppercase text-muted">{t("health.count")}</th></tr></thead>
                    <tbody>
                      {errors.map(([category, count]) => (
                        <tr key={category} className="border-t border-border">
                          <th scope="row" className="py-2 text-left font-normal">
                            {errorCategoryLabel(t, category)}
                            <span aria-hidden="true" className="mt-1 block h-1.5 rounded bg-danger" style={{ width: `${Math.max(4, (count / failedTotal) * 100)}%` }} />
                          </th>
                          <td className="py-2 text-right tabular-nums">{formatNumber(count, locale)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
            </Card>

            <Card title={t("health.stale")}>
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
              <p className="mt-3 text-xs text-muted">{t("health.staleNote")}</p>
            </Card>
          </div>

          <Card title={t("health.laya")} className="mt-5">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone={data.intent.enabled ? "ok" : "neutral"} icon={data.intent.enabled ? "●" : "○"}>{data.intent.enabled ? t("health.layaOn") : t("health.layaOff")}</Badge>
              {data.intent.enabled && data.intent.requests === 0 && <span className="text-sm text-muted">{t("health.layaNoRequests")}</span>}
              {data.intent.enabled && data.intent.requests > 0 && <span className="text-sm text-muted">{t("health.layaStats", { requests: data.intent.requests, p50: formatMs(data.intent.laya_latency_ms.p50, locale), p95: formatMs(data.intent.laya_latency_ms.p95, locale) })}</span>}
              {!data.intent.enabled && <span className="text-sm text-muted">{t("health.layaOffHint")}</span>}
            </div>
            {Object.keys(data.intent.fallbacks).length > 0 && (
              <p className="mt-2 text-sm">{t("health.layaFallbacks")}: {Object.entries(data.intent.fallbacks).map(([reason, count]) => `${reason} ×${count}`).join(", ")}</p>
            )}
          </Card>
        </>
      )}

      <Card title={t("health.timeline")} className="mt-5">
        {timeline.error && <ErrorState error={timeline.error} onRetry={() => timeline.mutate()} />}
        {!timeline.data && !timeline.error && <Loading />}
        {timeline.data && timeline.data.data.length === 0 && <EmptyState title={t("health.noRunsTitle")}>{t("health.noRunsBody")}</EmptyState>}
        {timeline.data && timeline.data.data.length > 0 && (
          <>
            <RunTimeline runs={timeline.data.data} />
            <p className="mt-2 text-xs text-muted">{t("health.timelineLegend")}</p>
            {timeline.data.data[0] && <p className="mt-1 text-xs text-muted">{t("health.lastRun", { when: formatRelative(timeline.data.data[0].created_at, locale) })}</p>}
          </>
        )}
      </Card>

      <Card
        title={t("health.recent")}
        className="mt-5"
        actions={
          <label className="flex items-center gap-2 text-sm">
            {t("health.filter")}
            <select className={`${INPUT_CLASS} w-auto py-1`} value={status} onChange={(event) => { setStatus(event.target.value as (typeof STATUS_FILTERS)[number]); setPage(1); }}>
              {STATUS_FILTERS.map((value) => <option key={value} value={value}>{t(FILTER_KEY[value])}</option>)}
            </select>
          </label>
        }
      >
        {runs.error && <ErrorState error={runs.error} onRetry={() => runs.mutate()} />}
        {!runs.data && !runs.error && <Loading />}
        {runs.data && runs.data.data.length === 0 && <p className="text-sm text-muted">{t("health.noMatching")}</p>}
        {runs.data && runs.data.data.length > 0 && (
          <>
            <RunsTable runs={runs.data.data} showKeyword />
            <Pagination meta={runs.data.meta} onPage={setPage} />
          </>
        )}
      </Card>
    </>
  );
}
