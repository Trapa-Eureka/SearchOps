import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Wrapper, mockApi, run } from "@/test/utils";
import { usePolledWhile } from "./api";

type Page = { data: { id: number; status: string }[] };
const active = (page: Page) => page.data.some((item) => item.status === "queued" || item.status === "running");

describe("usePolledWhile", () => {
  beforeEach(() => vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] }));
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  async function advance(ms: number) {
    await act(async () => {
      await vi.advanceTimersByTimeAsync(ms);
    });
  }

  it("keeps fetching while something is active, then stops", async () => {
    let status = "queued";
    const fetchMock = mockApi({ "GET /api/v1/x": () => ({ body: { data: [{ id: 1, status }] } }) });
    const { result } = renderHook(() => usePolledWhile<Page>("/api/v1/x", active), { wrapper: Wrapper });

    await advance(10);
    expect(result.current.data?.data[0].status).toBe("queued");
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await advance(2100);
    expect(fetchMock).toHaveBeenCalledTimes(2);

    status = "succeeded";
    await advance(2100);
    expect(result.current.data?.data[0].status).toBe("succeeded");
    const callsWhenDone = fetchMock.mock.calls.length;

    await advance(10_000);
    expect(fetchMock).toHaveBeenCalledTimes(callsWhenDone);
  });

  it("does not poll when nothing is active", async () => {
    const fetchMock = mockApi({ "GET /api/v1/x": { body: { data: [{ id: 1, status: "succeeded" }] } } });
    renderHook(() => usePolledWhile<Page>("/api/v1/x", active), { wrapper: Wrapper });

    await advance(10_000);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("starts polling when a run becomes active AFTER the page loaded with nothing running", async () => {
    // Regression: SWR's function-form refreshInterval never started its timer when the first
    // evaluation returned 0, so a search started later stayed "Queued" on screen forever.
    let items: { id: number; status: string }[] = [];
    const fetchMock = mockApi({ "GET /api/v1/x": () => ({ body: { data: items } }) });
    const { result } = renderHook(() => usePolledWhile<Page>("/api/v1/x", active), { wrapper: Wrapper });

    await advance(10);
    await advance(6000);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    items = [{ id: 1, status: "queued" }];
    await act(async () => {
      await result.current.mutate();
    });
    expect(result.current.data?.data[0].status).toBe("queued");
    const afterMutate = fetchMock.mock.calls.length;

    items = [{ id: 1, status: "succeeded" }];
    await advance(2100);
    expect(fetchMock.mock.calls.length).toBeGreaterThan(afterMutate);
    expect(result.current.data?.data[0].status).toBe("succeeded");
  });

  it("does nothing without a key", async () => {
    const fetchMock = mockApi({});
    renderHook(() => usePolledWhile<Page>(null, active), { wrapper: Wrapper });

    await advance(5000);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("keeps the real wait test data shape available", () => {
    expect(run({ status: "queued" })).toMatchObject({ status: "queued" });
  });
});

describe("usePolledWhile with real timers", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("reports a failing request as an error", async () => {
    mockApi({ "GET /api/v1/x": { status: 500, body: { error: { code: "boom", message: "x" } } } });
    const { result } = renderHook(() => usePolledWhile<Page>("/api/v1/x", active), { wrapper: Wrapper });

    await waitFor(() => expect(result.current.error).toBeDefined());
    expect(result.current.error).toMatchObject({ status: 500, code: "boom" });
  });
});
