import { screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { renderApp, series } from "@/test/utils";
import { OutcomeChart } from "./outcome-chart";

describe("OutcomeChart", () => {
  const data = series({ 2: { succeeded: 4, failed: 1 }, 3: { cache_hit: 2 }, 23: { active: 1, succeeded: 1 } });

  it("draws one bar group per busy slice, and hides the drawing from assistive technology", () => {
    const { container } = renderApp(<OutcomeChart series={data} />);
    const drawing = container.querySelector("svg[viewBox]") as SVGElement;

    expect(drawing).toHaveAttribute("aria-hidden", "true");
    expect(drawing.querySelectorAll("rect[fill^='url(']").length).toBe(5); // 2 + 1 + 2 segments
  });

  it("tells the outcomes apart by pattern as well as by colour", () => {
    const { container } = renderApp(<OutcomeChart series={data} />);
    const drawing = container.querySelector("svg[viewBox]") as SVGElement;
    const patterns = [...drawing.querySelectorAll("pattern")];

    expect(patterns).toHaveLength(4);
    expect(new Set(patterns.map((pattern) => pattern.innerHTML)).size).toBe(4);
    const used = new Set([...drawing.querySelectorAll("rect[fill^='url(']")].map((rect) => rect.getAttribute("fill")));
    expect(used.size).toBe(4);
  });

  it("puts the legend totals next to each outcome", () => {
    renderApp(<OutcomeChart series={data} />);
    const items = screen.getAllByRole("listitem").map((item) => item.textContent);
    expect(items).toEqual(["Answered by SerpApi5", "Answered from cache2", "Failed1", "Queued or running1"]);
  });

  it("has a table with a row per slice whose totals add up", () => {
    renderApp(<OutcomeChart series={data} />);
    const table = screen.getByRole("table", { name: "Search requests per time slice, by outcome" });
    const rows = within(table).getAllByRole("row").slice(1);

    expect(rows).toHaveLength(24);
    const totals = rows.map((row) => Number(within(row).getAllByRole("cell").at(-1)?.textContent));
    expect(totals[2]).toBe(5);
    expect(totals[3]).toBe(2);
    expect(totals[23]).toBe(2);
    expect(totals.reduce((sum, value) => sum + value, 0)).toBe(9);
  });

  it("shows tooltips with the words, not only numbers", () => {
    const { container } = renderApp(<OutcomeChart series={data} />);
    const titles = [...container.querySelectorAll("svg[viewBox] title")].map((title) => title.textContent);
    expect(titles.some((text) => text?.includes("Answered by SerpApi 4") && text.includes("Failed 1"))).toBe(true);
  });

  it("labels about eight slices on the time axis, in the user's locale", () => {
    const { container } = renderApp(<OutcomeChart series={data} />, { locale: "ko" });
    const labels = [...container.querySelectorAll("svg[viewBox] text")].filter((node) => /오전|오후/.test(node.textContent ?? ""));
    expect(labels.length).toBe(8);
  });

  it("explains an empty period instead of drawing an empty frame", () => {
    const { container } = renderApp(<OutcomeChart series={series()} />);
    expect(screen.getByText("No searches were made in this period.")).toBeInTheDocument();
    expect(container.querySelector("svg[viewBox]")).toBeNull();
  });

  it("formats the axis for each slice width", () => {
    const day = renderApp(<OutcomeChart series={series({ 1: { succeeded: 1 } }, 30, 86_400)} />);
    expect(screen.getAllByText(/^10\/\d+$/).length).toBeGreaterThan(0);
    day.unmount();
    renderApp(<OutcomeChart series={series({ 1: { succeeded: 1 } }, 12, 300)} />);
    expect(screen.getAllByText(/^\d+:\d\d (AM|PM)$/).length).toBeGreaterThan(0);
  });
});
