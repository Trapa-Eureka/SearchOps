import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { metrics, mockApi, renderApp } from "@/test/utils";
import { Shell } from "./shell";

const nav = vi.hoisted(() => ({ path: "/" }));
vi.mock("next/navigation", () => ({ usePathname: () => nav.path }));

beforeEach(() => { nav.path = "/"; document.cookie = "locale=; max-age=0"; });

const withMetrics = (over: Record<string, unknown> = {}) => mockApi({ "GET /api/v1/metrics/summary": { body: { data: metrics(over) } } });

describe("Shell", () => {
  it("has a skip link, one main landmark, a labelled navigation, and the local-only notice", () => {
    withMetrics();
    renderApp(<Shell><p>content</p></Shell>);
    expect(screen.getByRole("link", { name: "Skip to content" })).toHaveAttribute("href", "#main");
    expect(screen.getAllByRole("main")).toHaveLength(1);
    expect(screen.getByRole("navigation", { name: "Main navigation" })).toBeInTheDocument();
    expect(screen.getByRole("contentinfo")).toHaveTextContent(/Local use only/);
  });

  it("groups the navigation under headings", () => {
    withMetrics();
    renderApp(<Shell><p /></Shell>);
    const navigation = screen.getByRole("navigation");

    expect(within(navigation).getByText("Main menu")).toBeInTheDocument();
    expect(within(navigation).getByText("Diagnostics")).toBeInTheDocument();
    expect(within(navigation).getAllByRole("link").map((link) => link.textContent?.replace(/\d+.*$/, ""))).toEqual(["Overview", "Keywords", "Planner", "API health"]);
  });

  it.each([["/", "Overview"], ["/keywords", "Keywords"], ["/keywords/12", "Keywords"], ["/planner", "Planner"], ["/health", "API health"]])(
    "marks %s as the current page: %s", (path, label) => {
      nav.path = path;
      withMetrics();
      renderApp(<Shell><p /></Shell>);
      const current = within(screen.getByRole("navigation")).getAllByRole("link").filter((link) => link.getAttribute("aria-current") === "page");
      expect(current.map((link) => link.textContent)).toEqual([label]);
    },
  );

  it("does not mark Overview as current on other pages", () => {
    nav.path = "/health";
    withMetrics();
    renderApp(<Shell><p /></Shell>);
    expect(screen.getByRole("link", { name: "Overview" })).not.toHaveAttribute("aria-current");
  });

  it("shows real counts next to Keywords (stale) and API health (failed searches), with words for screen readers", async () => {
    withMetrics({ keywords: { total: 3, active: 3, scheduled: 1, stale: 2, no_data: 0 }, requests: { total: 10, by_status: { queued: 0, running: 0, succeeded: 5, failed: 5 }, by_trigger: { manual: 10, scheduled: 0 } } });
    renderApp(<Shell><p /></Shell>);

    expect(await screen.findByText("2 keywords with stale data")).toBeInTheDocument();
    expect(screen.getByText("5 failed searches in the last 24 hours")).toBeInTheDocument();
    // the badge does not change the link's own name
    expect(screen.getByRole("link", { name: "Keywords" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "API health" })).toBeInTheDocument();
  });

  it("shows no badges when everything is fine, while loading, or when the API is down", async () => {
    withMetrics();
    const { unmount } = renderApp(<Shell><p /></Shell>);
    expect(screen.queryByText(/keywords with stale data/)).not.toBeInTheDocument();
    await waitFor(() => expect(screen.queryByText(/failed searches in the last 24 hours/)).not.toBeInTheDocument());
    unmount();

    mockApi({ "GET /api/v1/metrics/summary": { status: 503, body: { error: { code: "http_error", message: "x" } } } });
    renderApp(<Shell><p /></Shell>);
    await new Promise((resolve) => setTimeout(resolve, 30));
    expect(screen.queryByText(/failed searches in the last 24 hours/)).not.toBeInTheDocument();
  });

  it("switches language, says which is selected, and remembers the choice", async () => {
    withMetrics();
    renderApp(<Shell><p /></Shell>);
    // the switch exists twice (header on small screens, sidebar on large); CSS shows one of them
    for (const button of screen.getAllByRole("button", { name: "English" })) expect(button).toHaveAttribute("aria-pressed", "true");

    await userEvent.click(screen.getAllByRole("button", { name: "Korean" })[0]);

    expect(screen.getByRole("link", { name: "개요" })).toBeInTheDocument();
    for (const button of screen.getAllByRole("button", { name: "Korean" })) expect(button).toHaveAttribute("aria-pressed", "true");
    expect(document.cookie).toContain("locale=ko");
    expect(document.documentElement.lang).toBe("ko");
  });
});
