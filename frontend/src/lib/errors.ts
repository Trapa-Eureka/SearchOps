import { ApiError } from "./api";
import type { MessageKey, Translate } from "./i18n";

const TITLES: Record<string, MessageKey> = {
  network_error: "error.network",
  bad_response: "error.badResponse",
  search_budget_exceeded: "error.budget",
  search_provider_not_configured: "error.providerNotConfigured",
  rate_limited: "error.rateLimited",
  not_found: "error.notFound",
  validation_failed: "error.validation",
  invalid_plan: "error.invalidPlan",
  not_confirmable: "error.notConfirmable",
  invalid_text: "error.invalidText",
  conflict: "error.conflict",
  bad_request: "error.badRequest",
};

/** A user-facing title for any thrown value, plus a detail line for the cases that carry numbers. */
export function describeError(error: unknown, t: Translate): { title: string; detail: string | null } {
  if (!(error instanceof ApiError)) return { title: t("error.unexpected"), detail: null };

  const key = TITLES[error.code];
  const title = key ? t(key) : t("error.http", { status: error.status });
  let detail: string | null = null;

  if (error.code === "search_budget_exceeded" && error.details) {
    detail = t("error.budgetDetail", { used: String(error.details.used ?? "?"), limit: String(error.details.limit ?? "?") });
  } else if (error.code === "not_confirmable" && typeof error.details?.reason === "string") {
    detail = t("plan.confirmBlocked", { reason: error.details.reason });
  } else if (error.code === "invalid_text" && typeof error.details?.text === "string") {
    detail = t("error.invalidTextDetail", { reason: error.details.text });
  }
  return { title, detail };
}
