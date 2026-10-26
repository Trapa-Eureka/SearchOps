import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

// Reads the real stylesheet, so changing a colour there is checked against WCAG AA (4.5:1 for text).
const css = readFileSync(resolve(process.cwd(), "src/app/globals.css"), "utf8");

function tokens(block: string): Record<string, string> {
  return Object.fromEntries([...block.matchAll(/--([a-z-]+):\s*(#[0-9a-fA-F]{6})\s*;/g)].map((match) => [match[1], match[2]]));
}

const rootBlock = css.match(/:root\s*{([^}]*)}/)?.[1] ?? "";
const darkBlock = css.match(/prefers-color-scheme:\s*dark\)\s*{\s*:root\s*{([^}]*)}/)?.[1] ?? "";
const light = tokens(rootBlock);
const dark = { ...light, ...tokens(darkBlock) };

function luminance(hex: string): number {
  const channels = [1, 3, 5].map((index) => parseInt(hex.slice(index, index + 2), 16) / 255);
  const [r, g, b] = channels.map((value) => (value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
const ratio = (a: string, b: string) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

// [text token, background token]
const PAIRS: [string, string][] = [
  ["text", "bg"], ["text", "surface"], ["muted", "bg"], ["muted", "surface"],
  ["accent", "surface"], ["accent", "bg"], ["accent-contrast", "accent"], ["accent-contrast", "accent-hover"],
  ["ok", "ok-bg"], ["warn", "warn-bg"], ["danger", "danger-bg"], ["info", "info-bg"],
  ["ok", "surface"], ["warn", "surface"], ["danger", "surface"], ["info", "surface"],
];

describe("colour tokens", () => {
  it("were found in both themes", () => {
    expect(Object.keys(light).length).toBeGreaterThan(15);
    expect(dark.bg).not.toBe(light.bg);
  });

  for (const [name, theme] of [["light", light], ["dark", dark]] as const) {
    for (const [fg, bg] of PAIRS) {
      it(`${name}: ${fg} on ${bg} has at least 4.5:1 contrast`, () => {
        expect(theme[fg], `missing token ${fg}`).toBeDefined();
        expect(theme[bg], `missing token ${bg}`).toBeDefined();
        expect(ratio(theme[fg], theme[bg])).toBeGreaterThanOrEqual(4.5);
      });
    }
  }

  it("white text on the danger button is readable (light theme)", () => {
    expect(ratio("#ffffff", light.danger)).toBeGreaterThanOrEqual(4.5);
  });

  it("computes the WCAG ratio correctly (black on white is 21:1)", () => {
    expect(ratio("#000000", "#ffffff")).toBeCloseTo(21, 5);
    expect(ratio("#777777", "#ffffff")).toBeCloseTo(4.48, 1);
  });
});
