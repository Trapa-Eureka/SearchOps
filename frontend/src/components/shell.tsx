"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { LOCALES, type Locale, type MessageKey } from "@/lib/i18n";
import { useLocale } from "./locale";
import { cx } from "./ui";

const NAV: { href: string; key: MessageKey }[] = [
  { href: "/", key: "nav.overview" },
  { href: "/keywords", key: "nav.keywords" },
  { href: "/planner", key: "nav.planner" },
  { href: "/health", key: "nav.health" },
];
const LOCALE_LABEL: Record<Locale, string> = { en: "English", ko: "한국어" };

export function Shell({ children }: { children: ReactNode }) {
  const { t, locale, setLocale } = useLocale();
  const pathname = usePathname();
  const isCurrent = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));

  return (
    <>
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:left-2 focus:top-2 focus:z-50 focus:rounded-md focus:bg-accent focus:px-3 focus:py-2 focus:text-accent-contrast">
        {t("shell.skip")}
      </a>
      <header className="border-b border-border bg-surface">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-x-6 gap-y-2 px-4 py-3">
          <Link href="/" className="text-lg font-bold tracking-tight">SearchOps</Link>
          <nav aria-label={t("shell.mainNav")} className="order-3 w-full sm:order-none sm:w-auto">
            <ul className="flex flex-wrap gap-1">
              {NAV.map((item) => (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    aria-current={isCurrent(item.href) ? "page" : undefined}
                    className={cx(
                      "block rounded-md px-3 py-1.5 text-sm font-medium focus-visible:outline-2 focus-visible:outline-accent",
                      isCurrent(item.href) ? "bg-accent text-accent-contrast" : "text-text hover:bg-bg",
                    )}
                  >
                    {t(item.key)}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
          <div role="group" aria-label={t("shell.language")} className="flex overflow-hidden rounded-md border border-border text-sm">
            {LOCALES.map((code) => (
              <button
                key={code}
                type="button"
                lang={code}
                aria-pressed={locale === code}
                onClick={() => setLocale(code)}
                className={cx("px-2.5 py-1 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent", locale === code ? "bg-accent text-accent-contrast" : "hover:bg-bg")}
              >
                {LOCALE_LABEL[code]}
              </button>
            ))}
          </div>
        </div>
      </header>
      <main id="main" tabIndex={-1} className="mx-auto max-w-6xl px-4 py-6 focus:outline-none">{children}</main>
      <footer className="mx-auto max-w-6xl px-4 pb-8 pt-2 text-xs text-muted">
        <p>{t("shell.localOnly")}</p>
      </footer>
    </>
  );
}
