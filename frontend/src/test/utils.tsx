import { render, type RenderOptions } from "@testing-library/react";
import type { ReactElement, ReactNode } from "react";
import { SWRConfig } from "swr";
import { LocaleProvider } from "@/components/locale";
import { ToastProvider } from "@/components/toast";
import { fetcher } from "@/lib/api";
import type { Locale } from "@/lib/i18n";
import { vi } from "vitest";

type Reply = { status?: number; body?: unknown };
type Route = Reply | ((request: { url: string; method: string; body: unknown }) => Reply);

/**
 * Replaces fetch with a table of routes keyed "METHOD /path" (query string ignored unless the
 * key contains one). Unmatched requests fail the test loudly. Returns the mock for assertions.
 */
export function mockApi(routes: Record<string, Route>) {
  const mock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const path = url.split("?")[0];
    const route = routes[`${method} ${url}`] ?? routes[`${method} ${path}`];
    if (!route) throw new Error(`Unexpected request: ${method} ${url}`);
    const reply = typeof route === "function" ? route({ url, method, body: init?.body ? JSON.parse(String(init.body)) : undefined }) : route;
    const status = reply.status ?? 200;
    return new Response(status === 204 ? null : JSON.stringify(reply.body ?? {}), { status, headers: { "Content-Type": "application/json" } });
  });
  vi.stubGlobal("fetch", mock);
  return mock;
}

export function Wrapper({ children, locale = "en" }: { children: ReactNode; locale?: Locale }) {
  return (
    <LocaleProvider initial={locale}>
      {/* A fresh cache per render so one test cannot see another's data. */}
      <SWRConfig value={{ fetcher, provider: () => new Map(), dedupingInterval: 0, shouldRetryOnError: false }}>
        <ToastProvider>{children}</ToastProvider>
      </SWRConfig>
    </LocaleProvider>
  );
}

export function renderApp(ui: ReactElement, options: RenderOptions & { locale?: Locale } = {}) {
  const { locale, ...rest } = options;
  return render(ui, { wrapper: ({ children }) => <Wrapper locale={locale}>{children}</Wrapper>, ...rest });
}

export const page = (data: unknown[], total = data.length, extra: Record<string, unknown> = {}) => ({
  data,
  meta: { page: 1, per_page: 25, total_count: total, total_pages: Math.max(1, Math.ceil(total / 25)), ...extra },
});

export const freshness = (overrides: Record<string, unknown> = {}) => ({
  state: "fresh", reason: null, last_success_at: new Date(Date.now() - 3_600_000).toISOString(), last_attempt_status: "succeeded",
  last_attempt_at: new Date(Date.now() - 3_600_000).toISOString(), ...overrides,
});

export const keyword = (overrides: Record<string, unknown> = {}) => ({
  id: 1, query: "react developer", engine: "google", country: "ph", language: "en", location: null, target_domain: "react.dev",
  active: true, schedule: "daily", created_at: "2026-10-20T00:00:00Z", updated_at: "2026-10-20T00:00:00Z", freshness: freshness(), ...overrides,
});

export const run = (overrides: Record<string, unknown> = {}) => ({
  id: 1, keyword_id: 1, status: "succeeded", triggered_by: "manual", started_at: "2026-10-26T01:00:00Z", finished_at: "2026-10-26T01:00:02Z",
  attempts: 1, upstream_calls: 1, upstream_latency_ms: 900, http_status: 200, error_category: null, error_message: null, attempt_log: [],
  cache_source: "none", cache: { hit: false, source_run_id: null, age_seconds: null }, result_count: 6, empty_results: false,
  request: { provider: "serpapi", engine: "google", query: "react developer", country: "ph", language: "en", location: null },
  rank: { target_domain: "react.dev", rank: 3, found: true }, created_at: "2026-10-26T01:00:00Z", ...overrides,
});

export const options = () => ({
  engines: ["google"], countries: ["us", "ph", "kr", "jp"], languages: ["en", "ko", "ja"], schedules: ["manual", "daily", "weekly"],
  limits: { query_max_length: 200, location_max_length: 100, max_keywords: 50, intent_text_max_length: 500, max_per_page: 100 },
  features: { intent_planning: true },
});

export const metrics = (overrides: Record<string, unknown> = {}) => ({
  window: { name: "24h", from: "2026-10-25T00:00:00Z", to: "2026-10-26T00:00:00Z" },
  requests: { total: 10, by_status: { queued: 0, running: 0, succeeded: 8, failed: 2 }, by_trigger: { manual: 6, scheduled: 4 } },
  upstream: { calls: 9, retries: 1, runs_succeeded: 8, runs_failed: 2, success_rate: 0.8, latency_ms: { samples: 10, p50: 900, p95: 4200, max: 15000 } },
  cache: { hits: 2, misses: 8, hit_rate: 0.2, ttl_seconds: 3600 },
  errors: { timeout: 1, auth: 1 },
  budget: { daily_limit: 20, used_today: 9, remaining_today: 11 },
  keywords: { total: 3, active: 2, scheduled: 1, stale: 1, no_data: 0 },
  queue: { queued: 0, running: 0, oldest_queued_age_seconds: null, workers_alive: 1 },
  intent: { enabled: true, requests: 0, by_outcome: {}, fallbacks: {}, laya_latency_ms: { samples: 0, p50: null, p95: null, max: null } },
  ...overrides,
});
