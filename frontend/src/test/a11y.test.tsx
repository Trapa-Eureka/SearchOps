import axe from "axe-core";
import { describe, expect, it, vi } from "vitest";
import { act } from "@testing-library/react";
import { Shell } from "@/components/shell";
import { freshness, keyword, metrics, mockApi, options, page, renderApp, run } from "@/test/utils";
import { HealthView } from "@/views/health";
import { KeywordDetailView } from "@/views/keyword-detail";
import { KeywordsView } from "@/views/keywords";
import { OverviewView } from "@/views/overview";
import { PlannerView } from "@/views/planner";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/",
  useSearchParams: () => new URLSearchParams(),
}));

// jsdom has no layout engine, so colour contrast cannot be computed here; src/lib/contrast.test.ts
// covers the design tokens instead.
async function violations(container: HTMLElement) {
  const result = await axe.run(container, { rules: { "color-contrast": { enabled: false } } });
  return result.violations.map((violation) => `${violation.id}: ${violation.help} (${violation.nodes.map((node) => node.target.join(" ")).join(", ")})`);
}

const entry = (id: number, rank: number | null) => ({
  id, search_run_id: id, target_domain: "react.dev", rank, found: rank !== null, captured_at: `2026-10-2${id}T00:00:00Z`,
  comparison: { status: rank === null ? "dropped" : "baseline", delta: null, previous_rank: null },
});
const routes = {
  "GET /api/v1/options": { body: { data: options() } },
  "GET /api/v1/metrics/summary": { body: { data: metrics() } },
  "GET /api/v1/keywords": { body: page([keyword(), keyword({ id: 2, query: "vue", freshness: freshness({ state: "stale", reason: "overdue" }) })]) },
  "GET /api/v1/keywords/1": { body: { data: keyword() } },
  "GET /api/v1/keywords/1/rank_history": { body: { data: [entry(2, null), entry(1, 4)], meta: { page: 1, per_page: 25, total_count: 2, total_pages: 1, freshness: freshness() } } },
  "GET /api/v1/keywords/1/searches": { body: page([run({ id: 1 }), run({ id: 2, status: "failed", error_category: "timeout", attempts: 3 })]) },
  "GET /api/v1/keywords/1/searches/1": { body: { data: { ...run({ id: 1 }), results: [{ position: 1, title: "React", url: "https://react.dev/", display_domain: "react.dev", snippet: "x" }] } } },
  "GET /api/v1/searches": { body: page([run({ id: 1, keyword: { id: 1, query: "react", country: "ph", language: "en", target_domain: "react.dev" } })]) },
};

async function settle() {
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 50)); });
}

describe.each([
  ["overview", <OverviewView key="o" />],
  ["keywords", <KeywordsView key="k" />],
  ["keyword detail", <KeywordDetailView key="d" id={1} />],
  ["planner", <PlannerView key="p" />],
  ["health", <HealthView key="h" />],
])("accessibility: %s", (_name, view) => {
  for (const locale of ["en", "ko"] as const) {
    it(`has no axe violations (${locale})`, async () => {
      mockApi(routes);
      const { container } = renderApp(<Shell>{view}</Shell>, { locale });
      await settle();
      expect(await violations(container)).toEqual([]);
    });
  }
});

describe("accessibility: loading and error states", () => {
  it("has no violations while loading", async () => {
    mockApi({ ...routes, "GET /api/v1/metrics/summary": () => new Promise(() => undefined) as never });
    const { container } = renderApp(<Shell><OverviewView /></Shell>);
    expect(await violations(container)).toEqual([]);
  });

  it("has no violations when the API is down", async () => {
    mockApi(Object.fromEntries(Object.keys(routes).map((key) => [key, { status: 503, body: { error: { code: "http_error", message: "x" } } }])));
    const { container } = renderApp(<Shell><OverviewView /></Shell>);
    await settle();
    expect(container.querySelector('[role="alert"]')).not.toBeNull();
    expect(await violations(container)).toEqual([]);
  });
});
