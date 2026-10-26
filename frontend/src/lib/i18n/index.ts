import { en } from "./en";
import { ko } from "./ko";

export type Locale = "en" | "ko";
export const LOCALES: readonly Locale[] = ["en", "ko"];
export const DEFAULT_LOCALE: Locale = "en";
export const LOCALE_COOKIE = "locale";

export type MessageKey = keyof typeof en;
export type Messages = Record<MessageKey, string>;
export type Vars = Record<string, string | number>;

const catalogs: Record<Locale, Messages> = { en, ko };

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (LOCALES as readonly string[]).includes(value);
}

/** The saved choice wins; otherwise the first supported language in Accept-Language; otherwise English. */
export function resolveLocale(cookieValue?: string | null, acceptLanguage?: string | null): Locale {
  if (isLocale(cookieValue)) return cookieValue;
  for (const part of (acceptLanguage ?? "").split(",")) {
    const tag = part.split(";")[0]?.trim().toLowerCase() ?? "";
    const base = tag.split("-")[0];
    if (isLocale(base)) return base;
  }
  return DEFAULT_LOCALE;
}

export function translate(locale: Locale, key: MessageKey, vars?: Vars): string {
  const template = catalogs[locale][key] ?? en[key];
  if (!vars) return template;
  return template.replace(/\{(\w+)\}/g, (match, name: string) => (name in vars ? String(vars[name]) : match));
}

export type Translate = (key: MessageKey, vars?: Vars) => string;
