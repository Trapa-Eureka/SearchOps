import { afterEach, describe, expect, it, vi } from "vitest";
import { api, ApiError, withQuery } from "./api";

function respond(status: number, body: unknown, raw = false) {
  vi.stubGlobal("fetch", vi.fn(async () => new Response(raw ? String(body) : JSON.stringify(body), { status })));
}

afterEach(() => vi.unstubAllGlobals());

describe("api client", () => {
  it("returns the parsed body of a successful request", async () => {
    respond(200, { data: [1, 2] });
    await expect(api.get("/api/v1/x")).resolves.toEqual({ data: [1, 2] });
  });

  it("sends JSON bodies with the right headers and never caches", async () => {
    respond(201, { data: {} });
    await api.post("/api/v1/keywords", { keyword: { query: "a" } });
    const [url, init] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/v1/keywords");
    expect(init).toMatchObject({ method: "POST", cache: "no-store", body: JSON.stringify({ keyword: { query: "a" } }) });
    expect(init.headers).toMatchObject({ "Content-Type": "application/json", Accept: "application/json" });
  });

  it("does not send a content type on a GET", async () => {
    respond(200, {});
    await api.get("/api/v1/x");
    const [, init] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(init.headers).not.toHaveProperty("Content-Type");
    expect(init.body).toBeUndefined();
  });

  it("treats 204 as no content", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 204 })));
    await expect(api.delete("/api/v1/keywords/1")).resolves.toBeUndefined();
  });

  it("turns the API error format into an ApiError", async () => {
    respond(429, { error: { code: "search_budget_exceeded", message: "Daily search budget reached", details: { limit: 5, used: 5 } } });
    const error = await api.post("/api/v1/keywords/1/searches").catch((caught) => caught);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 429, code: "search_budget_exceeded", message: "Daily search budget reached", details: { limit: 5, used: 5 } });
  });

  it("exposes field errors of a validation failure", async () => {
    respond(422, { error: { code: "validation_failed", message: "Validation failed", details: { query: ["can't be blank"], base: ["keyword limit reached"] } } });
    const error = (await api.post("/api/v1/keywords", {}).catch((caught) => caught)) as ApiError;
    expect(error.fieldErrors).toEqual({ query: ["can't be blank"], base: ["keyword limit reached"] });
  });

  it("has no field errors for other failures", async () => {
    respond(404, { error: { code: "not_found", message: "Resource not found" } });
    const error = (await api.get("/api/v1/keywords/0").catch((caught) => caught)) as ApiError;
    expect(error.fieldErrors).toEqual({});
  });

  it("reports an unreachable server as network_error", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("Failed to fetch"); }));
    await expect(api.get("/api/v1/x")).rejects.toMatchObject({ status: 0, code: "network_error" });
  });

  it("reports a non-JSON body as bad_response, keeping the status", async () => {
    respond(502, "<html>Bad Gateway</html>", true);
    await expect(api.get("/api/v1/x")).rejects.toMatchObject({ status: 502, code: "bad_response" });
  });

  it("falls back to a generic code when an error has no body shape", async () => {
    respond(500, { oops: true });
    await expect(api.get("/api/v1/x")).rejects.toMatchObject({ status: 500, code: "http_error" });
  });
});

describe("withQuery", () => {
  it("builds a query string and skips empty values", () => {
    expect(withQuery("/api/v1/x", { page: 2, status: "", q: undefined, none: null, active: false })).toBe("/api/v1/x?page=2&active=false");
  });

  it("leaves the path alone without parameters", () => {
    expect(withQuery("/api/v1/x")).toBe("/api/v1/x");
    expect(withQuery("/api/v1/x", { a: undefined })).toBe("/api/v1/x");
  });

  it("encodes special characters", () => {
    expect(withQuery("/api/v1/x", { q: "a b&c=d" })).toBe("/api/v1/x?q=a+b%26c%3Dd");
  });
});
