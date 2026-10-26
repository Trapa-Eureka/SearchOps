import { describe, expect, it } from "vitest";
import { ApiError } from "./api";
import { describeError } from "./errors";
import { translate } from "./i18n";

const t = (key: Parameters<typeof translate>[1], vars?: Parameters<typeof translate>[2]) => translate("en", key, vars);

describe("describeError", () => {
  it("explains the budget error with the numbers", () => {
    const error = new ApiError(429, "search_budget_exceeded", "x", { limit: 5, used: 5 });
    expect(describeError(error, t)).toEqual({ title: "The daily search budget is used up.", detail: "5 of 5 searches used today." });
  });

  it("tells the user what to do when SerpApi is not configured", () => {
    expect(describeError(new ApiError(503, "search_provider_not_configured", "x"), t).title).toMatch(/SERPAPI_API_KEY/);
  });

  it("distinguishes an unreachable server", () => {
    expect(describeError(new ApiError(0, "network_error", "x"), t).title).toMatch(/could not be reached/);
  });

  it("includes the reason a plan cannot be confirmed", () => {
    const error = new ApiError(422, "not_confirmable", "x", { reason: "engine_not_available" });
    expect(describeError(error, t).detail).toBe("Reason: engine_not_available");
  });

  it("falls back to the HTTP status for unknown codes", () => {
    expect(describeError(new ApiError(418, "teapot", "x"), t).title).toBe("The request failed (HTTP 418).");
  });

  it("never exposes an arbitrary thrown value", () => {
    expect(describeError(new Error("secret internals"), t)).toEqual({ title: "Something went wrong.", detail: null });
    expect(describeError("boom", t).title).toBe("Something went wrong.");
  });
});
