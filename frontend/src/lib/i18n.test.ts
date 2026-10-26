import { describe, expect, it } from "vitest";
import { en } from "./i18n/en";
import { ko } from "./i18n/ko";
import { DEFAULT_LOCALE, isLocale, resolveLocale, translate } from "./i18n";

const placeholders = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]).sort();

describe("catalogs", () => {
  it("provide exactly the same keys in both languages", () => {
    expect(Object.keys(ko).sort()).toEqual(Object.keys(en).sort());
  });

  it("have no empty or whitespace-only messages", () => {
    for (const [locale, catalog] of [["en", en], ["ko", ko]] as const) {
      for (const [key, value] of Object.entries(catalog)) expect(value.trim(), `${locale}:${key}`).not.toBe("");
    }
  });

  it("use the same {placeholders} in both languages, so no variable is dropped by a translation", () => {
    for (const key of Object.keys(en) as (keyof typeof en)[]) {
      expect(placeholders(ko[key]), key).toEqual(placeholders(en[key]));
    }
  });

  it("really translate (the Korean text is not just a copy of the English one)", () => {
    const sameAsEnglish = (Object.keys(en) as (keyof typeof en)[]).filter((key) => ko[key] === en[key] && /[A-Za-z]{4,}/.test(en[key]) && !key.startsWith("planner.example"));
    // Technical words such as "Laya", "p95", or "SerpApi" can legitimately match.
    expect(sameAsEnglish.length).toBeLessThan(8);
  });
});

describe("translate", () => {
  it("substitutes variables", () => {
    expect(translate("en", "common.pageOf", { page: 2, total: 5, count: 41 })).toBe("Page 2 of 5 (41 items)");
    expect(translate("ko", "common.pageOf", { page: 2, total: 5, count: 41 })).toBe("5쪽 중 2쪽 (총 41건)");
  });

  it("leaves an unknown placeholder visible instead of printing undefined", () => {
    expect(translate("en", "common.pageOf", { page: 1 })).toBe("Page 1 of {total} ({count} items)");
  });

  it("does not interpret variable values as templates", () => {
    expect(translate("en", "detail.deleteTitle", { query: "{count}" })).toBe("Delete “{count}”?");
  });

  it("returns the text unchanged without variables", () => {
    expect(translate("en", "nav.overview")).toBe("Overview");
    expect(translate("ko", "nav.overview")).toBe("개요");
  });
});

describe("resolveLocale", () => {
  it("prefers the saved choice", () => {
    expect(resolveLocale("ko", "en-US,en;q=0.9")).toBe("ko");
    expect(resolveLocale("en", "ko-KR")).toBe("en");
  });

  it("falls back to the first supported Accept-Language entry", () => {
    expect(resolveLocale(undefined, "ko-KR,ko;q=0.9,en;q=0.8")).toBe("ko");
    expect(resolveLocale(null, "fr-FR,fr;q=0.9,ko;q=0.5")).toBe("ko");
    expect(resolveLocale(null, "en-GB")).toBe("en");
  });

  it("ignores an invalid cookie and an unsupported language", () => {
    expect(resolveLocale("klingon", "ko")).toBe("ko");
    expect(resolveLocale("", "fr, de")).toBe(DEFAULT_LOCALE);
    expect(resolveLocale(undefined, undefined)).toBe(DEFAULT_LOCALE);
  });

  it("recognises locales", () => {
    expect(isLocale("ko")).toBe(true);
    expect(isLocale("fr")).toBe(false);
    expect(isLocale(undefined)).toBe(false);
  });
});
