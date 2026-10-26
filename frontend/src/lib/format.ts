import type { Locale } from "./i18n";

const EMPTY = "—";

export function formatNumber(value: number | null | undefined, locale: Locale): string {
  return value === null || value === undefined ? EMPTY : new Intl.NumberFormat(locale).format(value);
}

/** 0.8734 -> "87.3%". null means "no data", which is not 0%. */
export function formatPercent(ratio: number | null | undefined, locale: Locale): string {
  if (ratio === null || ratio === undefined) return EMPTY;
  return new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 1 }).format(ratio);
}

export function formatMs(ms: number | null | undefined, locale: Locale): string {
  if (ms === null || ms === undefined) return EMPTY;
  if (ms >= 1000) return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(ms / 1000)} s`;
  return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(ms)} ms`;
}

export function formatDateTime(iso: string | null | undefined, locale: Locale): string {
  if (!iso) return EMPTY;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return EMPTY;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" }).format(date);
}

const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ["day", 86_400],
  ["hour", 3_600],
  ["minute", 60],
  ["second", 1],
];

/** "3 minutes ago" / "3분 전", using the largest whole unit. */
export function formatRelative(iso: string | null | undefined, locale: Locale, now: Date = new Date()): string {
  if (!iso) return EMPTY;
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return EMPTY;
  const seconds = Math.round((then.getTime() - now.getTime()) / 1000);
  const formatter = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
  for (const [unit, size] of UNITS) {
    if (Math.abs(seconds) >= size || unit === "second") return formatter.format(Math.trunc(seconds / size), unit);
  }
  return EMPTY;
}

export function countryName(code: string, locale: Locale): string {
  try {
    return new Intl.DisplayNames(locale, { type: "region" }).of(code.toUpperCase()) ?? code;
  } catch {
    return code;
  }
}

export function languageName(code: string, locale: Locale): string {
  try {
    return new Intl.DisplayNames(locale, { type: "language" }).of(code) ?? code;
  } catch {
    return code;
  }
}

/** The host to show for a result: its display domain, else the URL's host. */
export function hostOf(url: string, displayDomain?: string | null): string {
  if (displayDomain) return displayDomain;
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

/** True when a result's host is the target domain or one of its subdomains. Mirrors DomainNormalizer.match? */
export function matchesDomain(host: string, target: string | null | undefined): boolean {
  if (!target) return false;
  const normalized = host.toLowerCase().replace(/^www\./, "");
  const wanted = target.toLowerCase().replace(/^www\./, "");
  return normalized === wanted || normalized.endsWith(`.${wanted}`);
}

/** Only http(s) links are rendered as links; anything else is shown as text. */
export function safeHref(url: string): string | null {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "http:" || parsed.protocol === "https:" ? parsed.toString() : null;
  } catch {
    return null;
  }
}
