// A small typed client for the Rails API. Every request goes to a same-origin /api path that the
// Next.js server forwards to Rails, so the browser never sees the Rails address or any credential.

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: Record<string, unknown> | null;

  constructor(status: number, code: string, message: string, details: Record<string, unknown> | null = null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }

  /** Field errors from a 422 validation_failed response: { query: ["can't be blank"] }. */
  get fieldErrors(): Record<string, string[]> {
    if (this.code !== "validation_failed" || !this.details) return {};
    return Object.fromEntries(
      Object.entries(this.details).map(([field, messages]) => [field, Array.isArray(messages) ? messages.map(String) : [String(messages)]]),
    );
  }
}

type Method = "GET" | "POST" | "PATCH" | "DELETE";

async function request<T>(method: Method, path: string, body?: unknown): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, {
      method,
      headers: { Accept: "application/json", ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: "no-store",
    });
  } catch {
    throw new ApiError(0, "network_error", "The server could not be reached");
  }

  if (response.status === 204) return undefined as T;

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new ApiError(response.status, "bad_response", "The server sent an unreadable response");
  }

  if (!response.ok) {
    const error = (payload as { error?: { code?: string; message?: string; details?: Record<string, unknown> } } | null)?.error;
    throw new ApiError(response.status, error?.code ?? "http_error", error?.message ?? `Request failed (${response.status})`, error?.details ?? null);
  }
  return payload as T;
}

export const api = {
  get: <T>(path: string) => request<T>("GET", path),
  post: <T>(path: string, body?: unknown) => request<T>("POST", path, body ?? {}),
  patch: <T>(path: string, body: unknown) => request<T>("PATCH", path, body),
  delete: (path: string) => request<void>("DELETE", path),
};

/** Builds "/api/v1/x?a=1&b=2", leaving out undefined, null, and empty values. */
export function withQuery(path: string, params: Record<string, string | number | boolean | null | undefined> = {}): string {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === "") continue;
    query.set(key, String(value));
  }
  const text = query.toString();
  return text ? `${path}?${text}` : path;
}

export const fetcher = <T,>(path: string) => api.get<T>(path);
