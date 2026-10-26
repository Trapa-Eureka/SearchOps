"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { FreshnessBadge, RankChange, RankValue } from "@/components/badges";
import { KeywordSwitcher } from "@/components/keyword-switcher";
import { KeywordForm, valuesFromKeyword } from "@/components/keyword-form";
import { useLocale } from "@/components/locale";
import { RankChart } from "@/components/rank-chart";
import { RunStrip } from "@/components/run-strip";
import { RankTable, ResultsTable, RunsTable } from "@/components/tables";
import { useToast } from "@/components/toast";
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Loading, Metric, PageTitle, Pagination } from "@/components/ui";
import { useStartSearch } from "@/hooks/actions";
import { useKeyword, useKeywordRuns, useKeywords, useOptions, useRankHistory, useRevalidateAll, useRun } from "@/hooks/api";
import { api, ApiError } from "@/lib/api";
import { describeError } from "@/lib/errors";
import { countryName, formatDateTime, formatMs, formatRelative, languageName } from "@/lib/format";
import type { KeywordInput, Run } from "@/lib/types";
import type { MessageKey } from "@/lib/i18n";

function ResultsPanel({ keywordId, runId, targetDomain }: { keywordId: number; runId: number; targetDomain: string | null }) {
  const { t, locale } = useLocale();
  const run = useRun(keywordId, runId);
  const detail: Run | undefined = run.data?.data;
  // A cache hit reuses an older result: the data was captured age_seconds before the hit was recorded.
  const capturedAt = detail
    ? detail.cache.hit && detail.cache.age_seconds !== null && detail.finished_at
      ? new Date(Date.parse(detail.finished_at) - detail.cache.age_seconds * 1000).toISOString()
      : (detail.finished_at ?? detail.created_at)
    : null;

  return (
    <Card icon="search" title={t("results.title")}>
      {run.error && <ErrorState error={run.error} onRetry={() => run.mutate()} />}
      {!detail && !run.error && <Loading />}
      {detail && (
        <>
          <dl className="mb-3 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
            <div className="flex gap-2"><dt className="text-muted">{t("results.captured")}</dt><dd>{formatDateTime(capturedAt, locale)}</dd></div>
            <div className="flex gap-2">
              <dt className="text-muted">{t("results.source")}</dt>
              <dd>{detail.cache.hit ? t("results.sourceCache", { id: detail.cache.source_run_id ?? "?" }) : t("results.sourceLive")}</dd>
            </div>
            <div className="flex gap-2"><dt className="text-muted">{t("results.engine")}</dt><dd>{[detail.request.engine ?? "google", detail.request.country?.toUpperCase(), detail.request.language].filter(Boolean).join(" · ")}</dd></div>
            {detail.rank && (
              <div className="flex gap-2">
                <dt className="text-muted">{t("results.targetRank")}</dt>
                <dd>{detail.rank.rank === null ? t("rank.notFound") : `#${detail.rank.rank}`} <span className="text-muted">({detail.rank.target_domain})</span></dd>
              </div>
            )}
          </dl>
          {detail.empty_results || (detail.results ?? []).length === 0
            ? <EmptyState title={t("results.emptyTitle")}>{t("results.emptyBody")}</EmptyState>
            : <ResultsTable results={detail.results ?? []} targetDomain={targetDomain} />}
          <p className="mt-2 text-xs text-muted">{t("results.windowNote", { count: detail.results?.length ?? 0 })}</p>
        </>
      )}
    </Card>
  );
}

export function KeywordDetailView({ id }: { id: number }) {
  const { t, locale } = useLocale();
  const router = useRouter();
  const toast = useToast();
  const startSearch = useStartSearch();
  const revalidate = useRevalidateAll();

  const [runPage, setRunPage] = useState(1);
  const [selectedRunId, setSelectedRunId] = useState<number | null>(null);
  const [editing, setEditing] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [refresh, setRefresh] = useState(false);

  const options = useOptions();
  const keyword = useKeyword(id);
  const siblings = useKeywords(1, 100);
  const history = useRankHistory(id);
  const runs = useKeywordRuns(id, runPage);

  if (keyword.error instanceof ApiError && keyword.error.status === 404) {
    return <EmptyState title={t("detail.notFound")} action={<Link href="/keywords"><Button>{t("detail.back")}</Button></Link>} />;
  }
  if (keyword.error) return <ErrorState error={keyword.error} onRetry={() => keyword.mutate()} />;
  if (!keyword.data) return <Loading />;

  const kw = keyword.data.data;
  const runList = runs.data?.data ?? [];
  const defaultRun = runList.find((run) => run.status === "succeeded") ?? null;
  const shownRunId = selectedRunId ?? defaultRun?.id ?? null;
  const entries = history.data?.data ?? [];

  async function runSearch() {
    setBusy(true);
    await startSearch(id, { refresh });
    setBusy(false);
  }

  async function save(payload: KeywordInput) {
    await api.patch(`/api/v1/keywords/${id}`, { keyword: payload });
    toast.push(t("detail.saved"), "success");
    setEditing(false);
    await revalidate();
  }

  async function remove() {
    setBusy(true);
    try {
      await api.delete(`/api/v1/keywords/${id}`);
      toast.push(t("detail.deleted"), "success");
      await revalidate();
      router.push("/keywords");
    } catch (error) {
      toast.push(describeError(error, t).title, "error");
      setBusy(false);
      setConfirmDelete(false);
    }
  }

  return (
    <>
      <p className="mb-2 text-sm"><Link href="/keywords" className="text-accent underline-offset-2 hover:underline">← {t("detail.back")}</Link></p>
      <PageTitle title={kw.query} description={`${countryName(kw.country, locale)} · ${languageName(kw.language, locale)}${kw.location ? ` · ${kw.location}` : ""}`}>
        <FreshnessBadge freshness={kw.freshness ?? history.data?.meta.freshness} withTime />
      </PageTitle>

      <KeywordSwitcher keywords={siblings.data?.data ?? []} currentId={id} />

      <dl className="mb-5 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Metric icon="star" iconTone="ok" label={t("keywordsTable.rank")}
          value={kw.target_domain && kw.activity?.rank ? <RankValue rank={kw.activity.rank.rank} /> : "—"}
          hint={kw.target_domain ? <>{kw.target_domain}{kw.activity?.rank && <> · <RankChange comparison={kw.activity.rank.comparison} /></>}</> : t("keywordsTable.noTarget")} />
        <Metric icon="gauge" label={t("keywordsTable.p95")}
          value={kw.activity && kw.activity.latency_ms.p95 !== null ? formatMs(kw.activity.latency_ms.p95, locale) : "—"}
          hint={kw.activity ? t("keywordsTable.p95Hint", { count: kw.activity.latency_ms.samples }) : undefined} />
        <Metric icon="clock" iconTone="warn" label={t("detail.lastGood")}
          value={kw.freshness?.last_success_at ? formatRelative(kw.freshness.last_success_at, locale) : "—"}
          hint={kw.freshness?.last_success_at ? formatDateTime(kw.freshness.last_success_at, locale) : t("freshness.noData")} />
        <Metric icon="pulse" label={t("keywordsTable.recent")} value={<RunStrip runs={kw.activity?.recent_runs ?? []} />} />
      </dl>

      <Card className="mb-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <dl className="grid gap-x-8 gap-y-1 text-sm sm:grid-cols-2">
            <div className="flex gap-2"><dt className="text-muted">{t("detail.market")}</dt><dd>{countryName(kw.country, locale)} · {languageName(kw.language, locale)}{kw.location ? ` · ${kw.location}` : ""}</dd></div>
            <div className="flex gap-2"><dt className="text-muted">{t("detail.target")}</dt><dd>{kw.target_domain ?? t("keywordsTable.noTarget")}</dd></div>
            <div className="flex gap-2"><dt className="text-muted">{t("detail.schedule")}</dt><dd>{t(`schedule.${kw.schedule}` as MessageKey)}</dd></div>
            <div className="flex gap-2"><dt className="text-muted">{t("detail.status")}</dt><dd>{kw.active ? <Badge tone="ok" icon="check">{t("detail.active")}</Badge> : <Badge icon="pause">{t("keywordsTable.paused")}</Badge>}</dd></div>
          </dl>
          <div className="flex flex-col items-start gap-2 sm:items-end">
            <div className="flex flex-wrap gap-2">
              <Button variant="primary" icon="refresh" onClick={runSearch} disabled={busy}>{t("keyword.searchNow")}</Button>
              <Button icon="pencil" onClick={() => setEditing(!editing)} aria-expanded={editing}>{t("detail.edit")}</Button>
              <Button variant="danger" icon="trash" onClick={() => setConfirmDelete(true)}>{t("detail.delete")}</Button>
            </div>
            <label className="flex items-center gap-2 text-xs text-muted">
              <input type="checkbox" className="size-4 accent-accent" checked={refresh} onChange={(event) => setRefresh(event.target.checked)} />
              {t("detail.forceRefresh")}
            </label>
          </div>
        </div>
        {editing && options.data && (
          <div className="mt-4 border-t border-border pt-4">
            <KeywordForm options={options.data.data} initial={valuesFromKeyword(kw)} submitLabel={t("common.save")} onSubmit={save} onCancel={() => setEditing(false)} />
          </div>
        )}
      </Card>

      <div className="grid grid-cols-1 gap-5">
        <Card icon="star" title={t("rank.title")} description={t("rankTable.hint")}>
          {history.error && <ErrorState error={history.error} onRetry={() => history.mutate()} />}
          {!history.data && !history.error && <Loading />}
          {history.data && !kw.target_domain && (
            <EmptyState title={t("rank.noTargetTitle")} action={<Button onClick={() => setEditing(true)}>{t("detail.edit")}</Button>}>{t("rank.noTargetBody")}</EmptyState>
          )}
          {history.data && kw.target_domain && entries.length === 0 && (
            <EmptyState title={t("rank.emptyTitle")}>{t("rank.emptyBody", { domain: kw.target_domain })}</EmptyState>
          )}
          {history.data && kw.target_domain && entries.length > 0 && (
            <div className="grid grid-cols-1 gap-6">
              <RankChart entries={entries} targetDomain={kw.target_domain} />
              <RankTable entries={entries} />
            </div>
          )}
        </Card>

        <Card icon="pulse" title={t("runs.title")}>
          {runs.error && <ErrorState error={runs.error} onRetry={() => runs.mutate()} />}
          {!runs.data && !runs.error && <Loading />}
          {runs.data && runList.length === 0 && <EmptyState title={t("runs.emptyTitle")}>{t("runs.emptyBody")}</EmptyState>}
          {runs.data && runList.length > 0 && (
            <>
              <RunsTable runs={runList} selectedId={shownRunId} onSelect={(run) => setSelectedRunId(run.id)} />
              <Pagination meta={runs.data.meta} onPage={setRunPage} />
            </>
          )}
        </Card>

        {shownRunId !== null && <ResultsPanel keywordId={id} runId={shownRunId} targetDomain={kw.target_domain} />}
      </div>

      <ConfirmDialog
        open={confirmDelete}
        title={t("detail.deleteTitle", { query: kw.query })}
        message={t("detail.deleteMessage")}
        confirmLabel={t("detail.delete")}
        busy={busy}
        onConfirm={remove}
        onCancel={() => setConfirmDelete(false)}
      />
    </>
  );
}
