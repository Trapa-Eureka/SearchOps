"use client";

import Link from "next/link";
import type { Keyword } from "@/lib/types";
import { RankValue } from "./badges";
import { useT } from "./locale";
import { cx } from "./ui";

/** How many keywords the strip offers. The Keywords page lists them all. */
const LIMIT = 30;

/** A row of keywords to jump between, each with its current rank, the current one raised. */
export function KeywordSwitcher({ keywords, currentId }: { keywords: Keyword[]; currentId: number }) {
  const t = useT();
  if (keywords.length < 2) return null;
  return (
    <nav aria-label={t("detail.switcher")} className="mb-5">
      <ul className="flex gap-2 overflow-x-auto pb-1">
        {keywords.slice(0, LIMIT).map((keyword) => {
          const current = keyword.id === currentId;
          return (
            <li key={keyword.id} className="shrink-0">
              <Link
                href={`/keywords/${keyword.id}`}
                aria-current={current ? "page" : undefined}
                className={cx(
                  "flex min-w-40 max-w-60 flex-col gap-0.5 rounded-xl px-4 py-2.5 focus-visible:outline-2 focus-visible:outline-accent",
                  current ? "bg-surface text-text shadow-card ring-2 ring-accent" : "bg-surface-2 text-muted hover:bg-surface hover:text-text",
                )}
              >
                <span className="truncate text-sm font-medium">{keyword.query}</span>
                <span className="text-xs">
                  {keyword.target_domain
                    ? (keyword.activity?.rank ? <RankValue rank={keyword.activity.rank.rank} /> : "—")
                    : t("detail.switcherNone")}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
