"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useMetrics } from "@/hooks/api";
import { LOCALES, type Locale, type MessageKey } from "@/lib/i18n";
import { formatNumber } from "@/lib/format";
import { Icon, type IconName } from "./icons";
import { useLocale } from "./locale";
import { cx } from "./ui";

type NavItem = { href: string; key: MessageKey; icon: IconName; badge?: "stale" | "failed" };
const GROUPS: { key: MessageKey; items: NavItem[] }[] = [
  {
    key: "nav.groupMain",
    items: [
      { href: "/", key: "nav.overview", icon: "overview" },
      { href: "/keywords", key: "nav.keywords", icon: "search", badge: "stale" },
      { href: "/planner", key: "nav.planner", icon: "sparkle" },
    ],
  },
  { key: "nav.groupDiagnostics", items: [{ href: "/health", key: "nav.health", icon: "pulse", badge: "failed" }] },
];
const LOCALE_LABEL: Record<Locale, string> = { en: "English", ko: "Korean" };

export function Shell({ children }: { children: ReactNode }) {
  const { t, locale, setLocale } = useLocale();
  const pathname = usePathname();
  const metrics = useMetrics("24h").data?.data;
  const isCurrent = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));

  // Real numbers from the API only. Nothing is shown while loading, on error, or when the count is zero.
  const badges = {
    stale: { count: metrics?.keywords.stale ?? 0, label: (count: number) => t("nav.staleBadge", { count }), tone: "bg-warn-bg text-warn" },
    failed: { count: metrics?.requests.by_status.failed ?? 0, label: (count: number) => t("nav.failedBadge", { count }), tone: "bg-danger-bg text-danger" },
  };

  return (
    <>
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:left-2 focus:top-2 focus:z-50 focus:rounded-lg focus:bg-accent focus:px-3 focus:py-2 focus:text-accent-contrast">
        {t("shell.skip")}
      </a>
      <div className="mx-auto flex min-h-screen max-w-[96rem] flex-col gap-4 p-3 lg:flex-row lg:gap-6 lg:p-5">
        <aside className="flex shrink-0 flex-col gap-5 lg:sticky lg:top-5 lg:h-[calc(100vh-2.5rem)] lg:w-60">
          <div className="flex items-center justify-between gap-3 px-1">
            <Link href="/" className="flex items-center gap-2.5 text-lg font-bold tracking-tight">
              <span className="flex size-8 items-center justify-center rounded-lg bg-accent text-accent-contrast"><Icon name="search" className="size-[1.1rem]" /></span>
              SearchOps
            </Link>
            <div role="group" aria-label={t("shell.language")} className="flex overflow-hidden rounded-lg bg-surface text-xs shadow-card lg:hidden">
              {LOCALES.map((code) => (
                <button key={code} type="button" aria-pressed={locale === code} onClick={() => setLocale(code)}
                  className={cx("px-2.5 py-1.5 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent", locale === code ? "bg-accent text-accent-contrast" : "hover:bg-surface-2")}>
                  {LOCALE_LABEL[code]}
                </button>
              ))}
            </div>
          </div>

          <nav aria-label={t("shell.mainNav")} className="flex flex-col gap-4">
            {GROUPS.map((group) => (
              <div key={group.key}>
                <p className="mb-1.5 hidden px-3 text-xs font-medium uppercase tracking-wide text-muted lg:block">{t(group.key)}</p>
                <ul className="flex flex-wrap gap-1 lg:flex-col">
                  {group.items.map((item) => {
                    const badge = item.badge ? badges[item.badge] : null;
                    const current = isCurrent(item.href);
                    return (
                      <li key={item.href} className="relative">
                        <Link
                          href={item.href}
                          aria-current={current ? "page" : undefined}
                          className={cx(
                            "flex items-center gap-2.5 rounded-lg py-2 pl-3 text-sm font-medium focus-visible:outline-2 focus-visible:outline-accent",
                            badge && badge.count > 0 ? "pr-11" : "pr-3",
                            current ? "bg-surface text-text shadow-card" : "text-muted hover:bg-surface/60 hover:text-text",
                          )}
                        >
                          <Icon name={item.icon} className={cx("size-[1.1rem]", current && "text-accent")} />
                          {t(item.key)}
                        </Link>
                        {badge && badge.count > 0 && (
                          <span className={cx("pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 rounded-full px-2 py-0.5 text-xs font-semibold tabular-nums", badge.tone)} title={badge.label(badge.count)}>
                            <span aria-hidden="true">{formatNumber(badge.count, locale)}</span>
                            <span className="sr-only">{badge.label(badge.count)}</span>
                          </span>
                        )}
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))}
          </nav>

          <div className="mt-auto hidden flex-col gap-3 lg:flex">
            <div>
              <p className="mb-1.5 px-3 text-xs font-medium uppercase tracking-wide text-muted">{t("nav.groupSettings")}</p>
              <div role="group" aria-label={t("shell.language")} className="flex overflow-hidden rounded-lg bg-surface text-sm shadow-card">
                {LOCALES.map((code) => (
                  <button key={code} type="button" aria-pressed={locale === code} onClick={() => setLocale(code)}
                    className={cx("flex-1 px-2.5 py-2 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent", locale === code ? "bg-accent text-accent-contrast" : "hover:bg-surface-2")}>
                    {LOCALE_LABEL[code]}
                  </button>
                ))}
              </div>
            </div>
            <p className="px-1 text-xs leading-snug text-muted">{t("shell.localOnly")}</p>
          </div>
        </aside>

        <main id="main" tabIndex={-1} className="min-w-0 flex-1 rounded-2xl bg-surface p-4 shadow-card focus:outline-none sm:p-6 lg:p-8">
          {children}
          <footer className="mt-8 text-xs text-muted lg:hidden"><p>{t("shell.localOnly")}</p></footer>
        </main>
      </div>
    </>
  );
}
