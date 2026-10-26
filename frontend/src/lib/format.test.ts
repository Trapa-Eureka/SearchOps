import { describe, expect, it } from "vitest";
import { countryName, formatDateTime, formatMs, formatNumber, formatPercent, formatRelative, hostOf, languageName, matchesDomain, safeHref } from "./format";

describe("numbers", () => {
  it("shows a dash for no data, never NaN or 0%", () => {
    expect(formatPercent(null, "en")).toBe("—");
    expect(formatPercent(undefined, "en")).toBe("—");
    expect(formatMs(null, "en")).toBe("—");
    expect(formatNumber(null, "en")).toBe("—");
  });

  it("formats a real zero as zero", () => {
    expect(formatPercent(0, "en")).toBe("0%");
    expect(formatMs(0, "en")).toBe("0 ms");
    expect(formatNumber(0, "en")).toBe("0");
  });

  it("formats percentages with at most one decimal", () => {
    expect(formatPercent(0.8734, "en")).toBe("87.3%");
    expect(formatPercent(1, "en")).toBe("100%");
  });

  it("switches latency to seconds at 1000 ms", () => {
    expect(formatMs(840, "en")).toBe("840 ms");
    expect(formatMs(1000, "en")).toBe("1 s");
    expect(formatMs(15_000, "en")).toBe("15 s");
    expect(formatMs(1240, "en")).toBe("1.2 s");
  });
});

describe("dates", () => {
  const now = new Date("2026-10-26T12:00:00Z");

  it("describes the past relative to now in the locale", () => {
    expect(formatRelative("2026-10-26T11:57:00Z", "en", now)).toBe("3 minutes ago");
    expect(formatRelative("2026-10-26T09:00:00Z", "en", now)).toBe("3 hours ago");
    expect(formatRelative("2026-10-25T12:00:00Z", "en", now)).toBe("yesterday");
    expect(formatRelative("2026-10-26T11:57:00Z", "ko", now)).toBe("3분 전");
  });

  it("handles missing and invalid input", () => {
    expect(formatRelative(null, "en", now)).toBe("—");
    expect(formatRelative("not a date", "en", now)).toBe("—");
    expect(formatDateTime(null, "en")).toBe("—");
    expect(formatDateTime("nope", "en")).toBe("—");
  });

  it("formats an absolute date in the locale", () => {
    expect(formatDateTime("2026-10-26T12:00:00Z", "en")).toMatch(/Oct 26, 2026/);
    expect(formatDateTime("2026-10-26T12:00:00Z", "ko")).toMatch(/2026\. 10\. 2[67]\./);
  });
});

describe("names", () => {
  it("localizes country and language names, falling back to the code", () => {
    expect(countryName("ph", "en")).toBe("Philippines");
    expect(countryName("kr", "ko")).toBe("대한민국");
    expect(languageName("ko", "en")).toBe("Korean");
    expect(countryName("not-a-code", "en")).toBe("not-a-code");
  });
});

describe("domains and links", () => {
  it("matches the target and its subdomains, not look-alikes (mirrors the server rule)", () => {
    expect(matchesDomain("react.dev", "react.dev")).toBe(true);
    expect(matchesDomain("www.react.dev", "react.dev")).toBe(true);
    expect(matchesDomain("blog.react.dev", "REACT.dev")).toBe(true);
    expect(matchesDomain("notreact.dev", "react.dev")).toBe(false);
    expect(matchesDomain("react.dev.evil.net", "react.dev")).toBe(false);
    expect(matchesDomain("react.dev", "blog.react.dev")).toBe(false);
  });

  it("matches nothing without a target", () => {
    expect(matchesDomain("react.dev", null)).toBe(false);
    expect(matchesDomain("react.dev", "")).toBe(false);
  });

  it("prefers the display domain and falls back to the URL host", () => {
    expect(hostOf("https://a.example.com/x", "example.com")).toBe("example.com");
    expect(hostOf("https://a.example.com/x", null)).toBe("a.example.com");
    expect(hostOf("not a url")).toBe("not a url");
  });

  it("only allows http and https links", () => {
    expect(safeHref("https://example.com/a?b=1")).toBe("https://example.com/a?b=1");
    expect(safeHref("http://example.com")).toBe("http://example.com/");
    expect(safeHref("javascript:alert(1)")).toBeNull();
    expect(safeHref("data:text/html,<script>alert(1)</script>")).toBeNull();
    expect(safeHref("//example.com")).toBeNull();
    expect(safeHref("not a url")).toBeNull();
  });
});
