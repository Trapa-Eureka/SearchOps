"use client";

import { useCallback } from "react";
import { useT } from "@/components/locale";
import { useToast } from "@/components/toast";
import { api, withQuery } from "@/lib/api";
import { describeError } from "@/lib/errors";
import type { MessageKey } from "@/lib/i18n";
import type { SearchOutcome, SearchStarted } from "@/lib/types";
import { useRevalidateAll } from "./api";

export const OUTCOME_KEY: Record<SearchOutcome, MessageKey> = {
  enqueued: "search.enqueued",
  deduplicated: "search.deduplicated",
  cache_hit: "search.cacheHit",
};

/** POST a search. The API only queues it (202) or answers from cache (200); the lists poll for the result. */
export function useStartSearch() {
  const t = useT();
  const toast = useToast();
  const revalidate = useRevalidateAll();

  return useCallback(
    async (keywordId: number, options: { refresh?: boolean } = {}): Promise<SearchStarted | null> => {
      try {
        const started = await api.post<SearchStarted>(
          withQuery(`/api/v1/keywords/${keywordId}/searches`, { refresh: options.refresh ? "true" : undefined }),
        );
        toast.push(t(OUTCOME_KEY[started.meta.outcome]), started.meta.outcome === "cache_hit" ? "info" : "success");
        await revalidate();
        return started;
      } catch (error) {
        const { title, detail } = describeError(error, t);
        toast.push(detail ? `${title} ${detail}` : title, "error");
        return null;
      }
    },
    [revalidate, t, toast],
  );
}
