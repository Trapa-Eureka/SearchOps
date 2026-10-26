import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { freshness, keyword, mockApi, options, page, renderApp } from "@/test/utils";
import { KeywordsView } from "./keywords";

const nav = vi.hoisted(() => ({ search: "" }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/keywords",
  useSearchParams: () => new URLSearchParams(nav.search),
}));

const list = [
  keyword({ id: 1, query: "react developer" }),
  keyword({ id: 2, query: "vue developer", freshness: freshness({ state: "stale", reason: "last_attempt_failed" }) }),
  keyword({ id: 3, query: "python tutorial", active: false, target_domain: null, schedule: "weekly", freshness: freshness({ state: "no_data", last_success_at: null }) }),
];
const baseRoutes = () => ({ "GET /api/v1/options": { body: { data: options() } }, "GET /api/v1/keywords": { body: page(list) } });

beforeEach(() => { nav.search = ""; });

describe("Keywords", () => {
  it("lists keywords with market, target, schedule, and how current their data is", async () => {
    mockApi(baseRoutes());
    renderApp(<KeywordsView />);
    const table = await screen.findByRole("table", { name: "Tracked keywords" });

    const rows = within(table).getAllByRole("row").slice(1);
    expect(rows).toHaveLength(3);
    expect(within(rows[0]).getByRole("link", { name: "react developer" })).toHaveAttribute("href", "/keywords/1");
    expect(within(rows[0]).getByText("PH · en")).toBeInTheDocument();
    expect(within(rows[0]).getByText("react.dev")).toBeInTheDocument();
    expect(within(rows[0]).getByText("Daily")).toBeInTheDocument();
    expect(within(rows[1]).getByText(/Stale: last attempt failed/)).toBeInTheDocument();
    expect(within(rows[2]).getByText("Paused")).toBeInTheDocument();
    expect(within(rows[2]).getByText("none")).toBeInTheDocument();
    expect(within(rows[2]).getByText("No data yet")).toBeInTheDocument();
  });

  it("shows how many of the allowed keywords exist", async () => {
    mockApi(baseRoutes());
    renderApp(<KeywordsView />);
    expect(await screen.findByText("3 of 50 keywords")).toBeInTheDocument();
  });

  it("opens the form by itself when there is nothing yet", async () => {
    mockApi({ ...baseRoutes(), "GET /api/v1/keywords": { body: page([]) } });
    renderApp(<KeywordsView />);

    expect(await screen.findByText("No keywords yet")).toBeInTheDocument();
    expect(await screen.findByRole("textbox", { name: /Search query/ })).toBeInTheDocument();
  });

  it("creates a keyword, confirms it, closes the form, and reloads the list", async () => {
    let created = false;
    const fetchMock = mockApi({
      ...baseRoutes(),
      "GET /api/v1/keywords": () => ({ body: page(created ? [...list, keyword({ id: 4, query: "svelte developer" })] : list) }),
      "POST /api/v1/keywords": () => { created = true; return { status: 201, body: { data: keyword({ id: 4 }) } }; },
    });
    renderApp(<KeywordsView />);
    await screen.findByRole("table");

    await userEvent.click(screen.getByRole("button", { name: "Add a keyword" }));
    await userEvent.type(await screen.findByRole("textbox", { name: /Search query/ }), "svelte developer");
    await userEvent.click(screen.getByRole("button", { name: "Create keyword" }));

    expect(await screen.findByText("Keyword created.")).toBeInTheDocument();
    expect(await screen.findByRole("link", { name: "svelte developer" })).toBeInTheDocument();
    expect(screen.queryByRole("textbox", { name: /Search query/ })).not.toBeInTheDocument();
    const post = fetchMock.mock.calls.find(([, init]) => (init as RequestInit)?.method === "POST");
    expect(JSON.parse(String((post?.[1] as RequestInit).body))).toEqual({
      keyword: { query: "svelte developer", country: "us", language: "en", location: null, target_domain: null, schedule: "manual", active: true },
    });
  });

  it("keeps the form open and shows the API's message when it is rejected", async () => {
    mockApi({
      ...baseRoutes(),
      "POST /api/v1/keywords": { status: 422, body: { error: { code: "validation_failed", message: "x", details: { query: ["already exists with the same search settings"] } } } },
    });
    renderApp(<KeywordsView />);
    await screen.findByRole("table");
    await userEvent.click(screen.getByRole("button", { name: "Add a keyword" }));
    await userEvent.type(await screen.findByRole("textbox", { name: /Search query/ }), "react developer");
    await userEvent.click(screen.getByRole("button", { name: "Create keyword" }));

    expect(await screen.findByText("Search query: already exists with the same search settings")).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: /Search query/ })).toHaveValue("react developer");
  });

  it("pauses and resumes a keyword", async () => {
    const fetchMock = mockApi({ ...baseRoutes(), "PATCH /api/v1/keywords/1": { body: { data: keyword({ active: false }) } }, "PATCH /api/v1/keywords/3": { body: { data: keyword({ id: 3 }) } } });
    renderApp(<KeywordsView />);
    const table = await screen.findByRole("table");
    const rows = within(table).getAllByRole("row").slice(1);

    await userEvent.click(within(rows[0]).getByRole("button", { name: "Pause" }));
    expect(await screen.findByText(/Keyword paused/)).toBeInTheDocument();
    await userEvent.click(within(rows[2]).getByRole("button", { name: "Resume" }));
    expect(await screen.findByText("Keyword resumed.")).toBeInTheDocument();

    const bodies = fetchMock.mock.calls.filter(([, init]) => (init as RequestInit)?.method === "PATCH").map(([url, init]) => [url, JSON.parse(String((init as RequestInit).body))]);
    expect(bodies).toEqual([["/api/v1/keywords/1", { keyword: { active: false } }], ["/api/v1/keywords/3", { keyword: { active: true } }]]);
  });

  it("starts a search and says it was queued", async () => {
    const fetchMock = mockApi({ ...baseRoutes(), "POST /api/v1/keywords/1/searches": { status: 202, body: { data: {}, meta: { outcome: "enqueued" } } } });
    renderApp(<KeywordsView />);
    const rows = within(await screen.findByRole("table")).getAllByRole("row").slice(1);

    await userEvent.click(within(rows[0]).getByRole("button", { name: "Search now" }));

    expect(await screen.findByText("Search queued. The result appears in a few seconds.")).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([url, init]) => url === "/api/v1/keywords/1/searches" && (init as RequestInit).method === "POST")).toBe(true);
  });

  it("tells the user when a search was answered from the cache or was already running", async () => {
    mockApi({
      ...baseRoutes(),
      "POST /api/v1/keywords/1/searches": { status: 200, body: { data: {}, meta: { outcome: "cache_hit" } } },
      "POST /api/v1/keywords/2/searches": { status: 202, body: { data: {}, meta: { outcome: "deduplicated" } } },
    });
    renderApp(<KeywordsView />);
    const rows = within(await screen.findByRole("table")).getAllByRole("row").slice(1);

    await userEvent.click(within(rows[0]).getByRole("button", { name: "Search now" }));
    expect(await screen.findByText("Answered from a recent result; SerpApi was not called.")).toBeInTheDocument();
    await userEvent.click(within(rows[1]).getByRole("button", { name: "Search now" }));
    expect(await screen.findByText(/already queued or running/)).toBeInTheDocument();
  });

  it("explains a refused search instead of failing silently", async () => {
    mockApi({
      ...baseRoutes(),
      "POST /api/v1/keywords/1/searches": { status: 429, body: { error: { code: "search_budget_exceeded", message: "x", details: { limit: 5, used: 5 } } } },
    });
    renderApp(<KeywordsView />);
    const rows = within(await screen.findByRole("table")).getAllByRole("row").slice(1);

    await userEvent.click(within(rows[0]).getByRole("button", { name: "Search now" }));

    expect(await screen.findByText(/The daily search budget is used up\. 5 of 5 searches used today\./)).toBeInTheDocument();
    expect(within(rows[0]).getByRole("button", { name: "Search now" })).toBeEnabled();
  });

  it("opens the form prefilled from the planner's fallback link", async () => {
    nav.search = "query=react+developer&country=ph&language=en&target_domain=react.dev";
    mockApi(baseRoutes());
    renderApp(<KeywordsView />);

    expect(await screen.findByRole("textbox", { name: /Search query/ })).toHaveValue("react developer");
    expect(screen.getByRole("combobox", { name: /Country/ })).toHaveValue("ph");
    expect(screen.getByRole("textbox", { name: /Target domain/ })).toHaveValue("react.dev");
  });

  it("ignores prefilled values the API does not offer, and caps long ones", async () => {
    nav.search = `query=${"q".repeat(500)}&country=zz&language=xx&target_domain=${"d".repeat(400)}`;
    mockApi(baseRoutes());
    renderApp(<KeywordsView />);

    const query = await screen.findByRole("textbox", { name: /Search query/ });
    expect((query as HTMLInputElement).value).toHaveLength(200);
    expect(screen.getByRole("combobox", { name: /Country/ })).toHaveValue("us");
    expect(screen.getByRole("combobox", { name: /Language/ })).toHaveValue("en");
    expect((screen.getByRole("textbox", { name: /Target domain/ }) as HTMLInputElement).value).toHaveLength(253);
  });

  it("does not execute markup passed in the prefill link", async () => {
    nav.search = "query=%3Cimg+src%3Dx+onerror%3Dalert(1)%3E";
    mockApi(baseRoutes());
    renderApp(<KeywordsView />);

    expect(await screen.findByRole("textbox", { name: /Search query/ })).toHaveValue("<img src=x onerror=alert(1)>");
    expect(document.querySelector("img")).toBeNull();
  });

  it("shows an error and a retry when the list cannot load", async () => {
    let up = false;
    mockApi({ ...baseRoutes(), "GET /api/v1/keywords": () => (up ? { body: page(list) } : { status: 500, body: { error: { code: "http_error", message: "x" } } }) });
    renderApp(<KeywordsView />);

    const alert = await screen.findByRole("alert");
    up = true;
    await userEvent.click(within(alert).getByRole("button", { name: "Try again" }));
    expect(await screen.findByRole("table")).toBeInTheDocument();
  });

  it("pages through a long list", async () => {
    const fetchMock = mockApi({
      ...baseRoutes(),
      "GET /api/v1/keywords": ({ url }) => (url.includes("page=2") ? { body: page([keyword({ id: 30, query: "page two keyword" })], 26, { page: 2 }) } : { body: page(list, 26) }),
    });
    renderApp(<KeywordsView />);
    await screen.findByRole("table");

    await userEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(await screen.findByRole("link", { name: "page two keyword" })).toBeInTheDocument();
    await waitFor(() => expect(fetchMock.mock.calls.some(([url]) => String(url).includes("page=2"))).toBe(true));
  });
});
