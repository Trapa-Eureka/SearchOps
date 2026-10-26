import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { activity, keyword, renderApp } from "@/test/utils";
import type { Keyword } from "@/lib/types";
import { KeywordSwitcher } from "./keyword-switcher";

const list = [
  keyword({ id: 1, query: "react developer" }),
  keyword({ id: 2, query: "vue developer", activity: activity({ rank: { rank: null, found: false, captured_at: "2026-10-26T00:00:00Z", target_domain: "vuejs.org", comparison: { status: "dropped", delta: null, previous_rank: 4 } } }) }),
  keyword({ id: 3, query: "no target", target_domain: null, activity: activity({ rank: null }) }),
  keyword({ id: 4, query: "no snapshot yet", activity: activity({ rank: null }) }),
] as unknown as Keyword[];

describe("KeywordSwitcher", () => {
  it("is not shown when there is nothing to switch to", () => {
    renderApp(<KeywordSwitcher keywords={list.slice(0, 1)} currentId={1} />);
    expect(screen.queryByRole("navigation")).not.toBeInTheDocument();
  });

  it("links to each keyword and marks the current one", () => {
    renderApp(<KeywordSwitcher keywords={list} currentId={2} />);

    expect(screen.getByRole("navigation", { name: "Switch keyword" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /vue developer/ })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: /react developer/ })).not.toHaveAttribute("aria-current");
    expect(screen.getByRole("link", { name: /react developer/ })).toHaveAttribute("href", "/keywords/1");
  });

  it("shows each keyword's current rank, 'Not found' without a number, and no rank without a target", () => {
    renderApp(<KeywordSwitcher keywords={list} currentId={1} />);

    expect(screen.getByRole("link", { name: /react developer/ })).toHaveTextContent("#3");
    expect(screen.getByRole("link", { name: /vue developer/ })).toHaveTextContent("Not found");
    expect(screen.getByRole("link", { name: /vue developer/ })).not.toHaveTextContent("#0");
    expect(screen.getByRole("link", { name: /no target/ })).toHaveTextContent("no target");
    expect(screen.getByRole("link", { name: /no snapshot yet/ })).toHaveTextContent("—");
  });

  it("offers at most 30 keywords", () => {
    const many = Array.from({ length: 40 }, (_, index) => keyword({ id: index + 1, query: `k${index + 1}` })) as unknown as Keyword[];
    renderApp(<KeywordSwitcher keywords={many} currentId={1} />);
    expect(screen.getAllByRole("link")).toHaveLength(30);
  });
});
