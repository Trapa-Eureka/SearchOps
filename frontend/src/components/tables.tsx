"use client";

import Link from "next/link";
import type { Keyword, RankHistoryEntry, Run, SearchResultRow } from "@/lib/types";
import { formatDateTime, formatMs, formatRelative, hostOf, matchesDomain, safeHref } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";
import { CacheBadge, ChangeBadge, FreshnessBadge, RankValue, RunStatusBadge, TriggerBadge } from "./badges";
import { useLocale, useT } from "./locale";
import { Badge, Button, cx } from "./ui";

const TABLE = "w-full min-w-[34rem] border-collapse text-sm";
const TH = "border-b border-border px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted";
const TD = "border-b border-border px-3 py-2 align-top";

export const ERROR_KEY: Record<string, MessageKey> = {
  auth: "errorCategory.auth", quota: "errorCategory.quota", rate_limit: "errorCategory.rate_limit", network: "errorCategory.network",
  timeout: "errorCategory.timeout", invalid_request: "errorCategory.invalid_request", schema: "errorCategory.schema",
  upstream: "errorCategory.upstream", unknown: "errorCategory.unknown", budget: "errorCategory.budget", abandoned: "errorCategory.abandoned",
};

export function errorCategoryLabel(t: (key: MessageKey) => string, category: string): string {
  const key = ERROR_KEY[category];
  return key ? t(key) : category;
}

function Scroll({ children, label }: { children: React.ReactNode; label: string }) {
  const t = useT();
  // Wide tables scroll sideways inside their box instead of breaking the page layout. The box is
  // `relative` so that the absolutely positioned .sr-only labels in the table are contained and
  // clipped by it; otherwise they sit at the table's far edge and widen the whole page.
  return <div role="region" aria-label={t("table.scrollable", { name: label })} tabIndex={0} className="relative overflow-x-auto rounded-md focus-visible:outline-2 focus-visible:outline-accent">{children}</div>;
}

export function RankTable({ entries }: { entries: RankHistoryEntry[] }) {
  const t = useT();
  const { locale } = useLocale();
  return (
    <Scroll label={t("rankTable.caption")}>
      <table className={TABLE}>
        <caption className="sr-only">{t("rankTable.caption")}</caption>
        <thead>
          <tr>
            <th scope="col" className={TH}>{t("rankTable.captured")}</th>
            <th scope="col" className={TH}>{t("rankTable.rank")}</th>
            <th scope="col" className={TH}>{t("rankTable.change")}</th>
            <th scope="col" className={TH}>{t("rankTable.previous")}</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr key={entry.id}>
              <td className={TD}>{formatDateTime(entry.captured_at, locale)}</td>
              <td className={TD}><RankValue rank={entry.rank} /></td>
              <td className={TD}><ChangeBadge status={entry.comparison.status} delta={entry.comparison.delta} /></td>
              <td className={TD}>{entry.comparison.previous_rank === null ? "—" : `#${entry.comparison.previous_rank}`}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Scroll>
  );
}

function RunNote({ run }: { run: Run }) {
  const t = useT();
  if (run.status === "failed" && run.error_category) {
    return <span title={run.error_message ?? undefined} className="text-danger">{errorCategoryLabel(t, run.error_category)}</span>;
  }
  if (run.status === "succeeded") {
    if (run.empty_results) return <span className="text-muted">{t("run.emptyResult")}</span>;
    return <span>{t("run.resultCount", { count: run.result_count ?? 0 })}</span>;
  }
  return <span className="text-muted">—</span>;
}

export function RunsTable({ runs, selectedId, onSelect, showKeyword = false }: { runs: Run[]; selectedId?: number | null; onSelect?: (run: Run) => void; showKeyword?: boolean }) {
  const t = useT();
  const { locale } = useLocale();
  return (
    <Scroll label={t("runsTable.caption")}>
      <table className={TABLE}>
        <caption className="sr-only">{t("runsTable.caption")}</caption>
        <thead>
          <tr>
            <th scope="col" className={TH}>{t("runsTable.when")}</th>
            {showKeyword && <th scope="col" className={TH}>{t("runsTable.keyword")}</th>}
            <th scope="col" className={TH}>{t("runsTable.status")}</th>
            <th scope="col" className={TH}>{t("runsTable.outcome")}</th>
            <th scope="col" className={TH}>{t("runsTable.latency")}</th>
            <th scope="col" className={TH}>{t("runsTable.attempts")}</th>
            {onSelect && <th scope="col" className={TH}><span className="sr-only">{t("runsTable.actions")}</span></th>}
          </tr>
        </thead>
        <tbody>
          {runs.map((run) => (
            <tr key={run.id} className={cx(selectedId === run.id && "bg-info-bg/40")}>
              <td className={TD}>
                <time dateTime={run.created_at} title={formatDateTime(run.created_at, locale)}>{formatRelative(run.created_at, locale)}</time>
                <div className="mt-0.5"><TriggerBadge trigger={run.triggered_by} /></div>
              </td>
              {showKeyword && (
                <td className={TD}>
                  {run.keyword ? <Link href={`/keywords/${run.keyword.id}`} className="font-medium text-accent underline-offset-2 hover:underline">{run.keyword.query}</Link> : `#${run.keyword_id}`}
                </td>
              )}
              <td className={TD}>
                <div className="flex flex-wrap gap-1"><RunStatusBadge status={run.status} /><CacheBadge run={run} /></div>
              </td>
              <td className={TD}><RunNote run={run} /></td>
              <td className={TD}>{run.cache.hit ? "—" : formatMs(run.upstream_latency_ms, locale)}</td>
              <td className={TD}>
                {run.attempts > 1
                  ? <Badge tone="warn" icon="↻" title={t("runsTable.retriedHint")}>{t("runsTable.retries", { count: run.attempts - 1 })}</Badge>
                  : run.attempts}
              </td>
              {onSelect && (
                <td className={TD}>
                  <Button size="sm" variant={selectedId === run.id ? "primary" : "secondary"} aria-pressed={selectedId === run.id} disabled={run.status !== "succeeded"} onClick={() => onSelect(run)}>
                    {t("runsTable.viewResults")}
                  </Button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </Scroll>
  );
}

export function ResultsTable({ results, targetDomain }: { results: SearchResultRow[]; targetDomain: string | null }) {
  const t = useT();
  return (
    <Scroll label={t("resultsTable.caption")}>
      <table className={TABLE}>
        <caption className="sr-only">{t("resultsTable.caption")}</caption>
        <thead>
          <tr>
            <th scope="col" className={TH}>{t("resultsTable.position")}</th>
            <th scope="col" className={TH}>{t("resultsTable.result")}</th>
            <th scope="col" className={TH}>{t("resultsTable.domain")}</th>
          </tr>
        </thead>
        <tbody>
          {results.map((result) => {
            const host = hostOf(result.url, result.display_domain);
            const isTarget = matchesDomain(host, targetDomain);
            const href = safeHref(result.url);
            return (
              <tr key={result.position} className={cx(isTarget && "bg-ok-bg/50")}>
                <td className={cx(TD, "tabular-nums font-semibold")}>#{result.position}</td>
                <td className={TD}>
                  {href
                    ? <a href={href} target="_blank" rel="noopener noreferrer" className="font-medium text-accent underline-offset-2 hover:underline">{result.title ?? result.url}<span className="sr-only"> {t("common.opensNewTab")}</span></a>
                    : <span className="font-medium">{result.title ?? result.url}</span>}
                  {result.snippet && <p className="mt-0.5 text-muted">{result.snippet}</p>}
                </td>
                <td className={TD}>
                  {host}
                  {isTarget && <div className="mt-0.5"><Badge tone="ok" icon="★">{t("resultsTable.target")}</Badge></div>}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </Scroll>
  );
}

export function KeywordsTable({ keywords, onToggleActive, onSearch, busyId }: {
  keywords: Keyword[]; onToggleActive: (keyword: Keyword) => void; onSearch: (keyword: Keyword) => void; busyId: number | null;
}) {
  const t = useT();
  return (
    <Scroll label={t("keywordsTable.caption")}>
      <table className={cx(TABLE, "min-w-[46rem]")}>
        <caption className="sr-only">{t("keywordsTable.caption")}</caption>
        <thead>
          <tr>
            <th scope="col" className={TH}>{t("keywordsTable.keyword")}</th>
            <th scope="col" className={TH}>{t("keywordsTable.market")}</th>
            <th scope="col" className={TH}>{t("keywordsTable.target")}</th>
            <th scope="col" className={TH}>{t("keywordsTable.schedule")}</th>
            <th scope="col" className={TH}>{t("keywordsTable.freshness")}</th>
            <th scope="col" className={TH}><span className="sr-only">{t("keywordsTable.actions")}</span></th>
          </tr>
        </thead>
        <tbody>
          {keywords.map((keyword) => (
            <tr key={keyword.id} className={cx(!keyword.active && "opacity-70")}>
              <td className={TD}>
                <Link href={`/keywords/${keyword.id}`} className="font-medium text-accent underline-offset-2 hover:underline">{keyword.query}</Link>
                {!keyword.active && <div className="mt-0.5"><Badge icon="⏸">{t("keywordsTable.paused")}</Badge></div>}
              </td>
              <td className={TD}>{keyword.country.toUpperCase()} · {keyword.language}{keyword.location ? ` · ${keyword.location}` : ""}</td>
              <td className={TD}>{keyword.target_domain ?? <span className="text-muted">{t("keywordsTable.noTarget")}</span>}</td>
              <td className={TD}>{t(`schedule.${keyword.schedule}` as MessageKey)}</td>
              <td className={TD}><FreshnessBadge freshness={keyword.freshness} withTime /></td>
              <td className={TD}>
                <div className="flex flex-wrap gap-1.5">
                  <Button size="sm" disabled={busyId === keyword.id} onClick={() => onSearch(keyword)}>{t("keyword.searchNow")}</Button>
                  <Button size="sm" aria-pressed={keyword.active} disabled={busyId === keyword.id} onClick={() => onToggleActive(keyword)}>
                    {keyword.active ? t("keywordsTable.pause") : t("keywordsTable.resume")}
                  </Button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Scroll>
  );
}
