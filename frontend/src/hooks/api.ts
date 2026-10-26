"use client";

import { useState } from "react";
import useSWR, { useSWRConfig, type SWRResponse } from "swr";
import { withQuery } from "@/lib/api";
import type { Keyword, Metrics, Options, Paginated, RankHistory, Run } from "@/lib/types";

const ACTIVE = new Set(["queued", "running"]);
const POLL_MS = 2000;

/**
 * Fetches a key and keeps re-fetching every POLL_MS while `active(data)` is true, then stops.
 *
 * SWR's function form of refreshInterval is not enough here: if it returns 0 on the first
 * evaluation (nothing is running when the page opens), SWR never starts its timer, so a search
 * started later would stay "queued" on screen. A plain number that changes with the data does
 * restart the timer. The state is adjusted during render, which is React's pattern for values
 * derived from other values.
 */
export function usePolledWhile<T>(key: string | null, active: (data: T) => boolean): SWRResponse<T> {
  const [interval, setInterval] = useState(0);
  const response = useSWR<T>(key, { refreshInterval: interval });
  const wanted = response.data !== undefined && active(response.data) ? POLL_MS : 0;
  if (wanted !== interval) setInterval(wanted);
  return response;
}

const anyRunActive = (page: Paginated<Run>) => page.data.some((run) => ACTIVE.has(run.status));

export function useOptions() {
  return useSWR<{ data: Options }>("/api/v1/options", { revalidateOnFocus: false, dedupingInterval: 60_000 });
}

export function useMetrics(window: string) {
  return useSWR<{ data: Metrics }>(withQuery("/api/v1/metrics/summary", { window }), { refreshInterval: 15_000 });
}

export function useKeywords(page: number, perPage = 25) {
  return useSWR<Paginated<Keyword>>(withQuery("/api/v1/keywords", { page, per_page: perPage }));
}

export function useKeyword(id: number | null) {
  return useSWR<{ data: Keyword }>(id === null ? null : `/api/v1/keywords/${id}`);
}

export function useRankHistory(id: number | null, perPage = 50) {
  return useSWR<RankHistory>(id === null ? null : withQuery(`/api/v1/keywords/${id}/rank_history`, { per_page: perPage }));
}

export function useKeywordRuns(id: number | null, page: number) {
  return usePolledWhile<Paginated<Run>>(id === null ? null : withQuery(`/api/v1/keywords/${id}/searches`, { page, per_page: 10 }), anyRunActive);
}

export function useRun(keywordId: number | null, runId: number | null) {
  return usePolledWhile<{ data: Run }>(
    keywordId === null || runId === null ? null : `/api/v1/keywords/${keywordId}/searches/${runId}`,
    (latest) => ACTIVE.has(latest.data.status),
  );
}

export function useRecentRuns(params: { status?: string; per_page?: number; page?: number } = {}) {
  return usePolledWhile<Paginated<Run>>(withQuery("/api/v1/searches", { per_page: 25, ...params }), anyRunActive);
}

/** Re-fetch everything that depends on keywords and runs after a change. */
export function useRevalidateAll() {
  const { mutate } = useSWRConfig();
  return () => mutate((key) => typeof key === "string" && (key.startsWith("/api/v1/keywords") || key.startsWith("/api/v1/searches") || key.startsWith("/api/v1/metrics")));
}
