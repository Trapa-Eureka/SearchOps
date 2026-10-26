import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { renderApp } from "@/test/utils";
import { Shell } from "./shell";

const nav = vi.hoisted(() => ({ path: "/" }));
vi.mock("next/navigation", () => ({ usePathname: () => nav.path }));

beforeEach(() => { nav.path = "/"; document.cookie = "locale=; max-age=0"; });

describe("Shell", () => {
  it("has a skip link, one main landmark, and a labelled navigation", () => {
    renderApp(<Shell><p>content</p></Shell>);
    expect(screen.getByRole("link", { name: "Skip to content" })).toHaveAttribute("href", "#main");
    expect(screen.getAllByRole("main")).toHaveLength(1);
    expect(screen.getByRole("navigation", { name: "Main navigation" })).toBeInTheDocument();
    expect(screen.getByRole("contentinfo")).toBeInTheDocument();
  });

  it.each([["/", "Overview"], ["/keywords", "Keywords"], ["/keywords/12", "Keywords"], ["/planner", "Planner"], ["/health", "API health"]])(
    "marks %s as the current page: %s", (path, label) => {
      nav.path = path;
      renderApp(<Shell><p /></Shell>);
      const current = within(screen.getByRole("navigation")).getAllByRole("link").filter((link) => link.getAttribute("aria-current") === "page");
      expect(current.map((link) => link.textContent)).toEqual([label]);
    },
  );

  it("does not mark Overview as current on other pages", () => {
    nav.path = "/health";
    renderApp(<Shell><p /></Shell>);
    expect(screen.getByRole("link", { name: "Overview" })).not.toHaveAttribute("aria-current");
  });

  it("switches language, says which is selected, and remembers the choice", async () => {
    renderApp(<Shell><p /></Shell>);
    expect(screen.getByRole("button", { name: "English" })).toHaveAttribute("aria-pressed", "true");

    await userEvent.click(screen.getByRole("button", { name: "한국어" }));

    expect(screen.getByRole("link", { name: "개요" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "한국어" })).toHaveAttribute("aria-pressed", "true");
    expect(document.cookie).toContain("locale=ko");
    expect(document.documentElement.lang).toBe("ko");
  });
});
