"use client";

import Link from "next/link";
import { useState } from "react";
import { api, ApiError } from "@/lib/api";
import { describeError } from "@/lib/errors";
import { countryName, formatPercent, languageName } from "@/lib/format";
import type { MessageKey, Translate } from "@/lib/i18n";
import type { FieldProvenance, IntentPlan, Options } from "@/lib/types";
import { useRevalidateAll } from "@/hooks/api";
import { Badge, Button, Card, ErrorState, Field, INPUT_CLASS } from "./ui";
import { useLocale } from "./locale";
import { useToast } from "./toast";

export const REASON_KEY: Record<string, MessageKey> = {
  low_confidence: "plan.reason.low_confidence",
  missing_fields: "plan.reason.missing_fields",
  ambiguous_keyword: "plan.reason.ambiguous_keyword",
  keyword_not_found: "plan.reason.keyword_not_found",
  invalid_fields: "plan.reason.invalid_fields",
  out_of_scope: "plan.reason.out_of_scope",
  engine_not_available: "plan.reason.engine_not_available",
  laya_disabled: "plan.reason.laya_disabled",
  classifier_timeout: "plan.reason.classifier_timeout",
  classifier_unavailable: "plan.reason.classifier_unavailable",
  classifier_busy: "plan.reason.classifier_busy",
  classifier_auth: "plan.reason.classifier_auth",
  classifier_bad_request: "plan.reason.classifier_bad_request",
  classifier_server_error: "plan.reason.classifier_server_error",
  classifier_invalid_response: "plan.reason.classifier_invalid_response",
};
const INTENT_KEY: Record<string, MessageKey> = {
  organic_rank_tracking: "intent.organic_rank_tracking",
  job_search: "intent.job_search",
  search_history: "intent.search_history",
  unsupported: "intent.unsupported",
};
const NOTE_KEY: Record<string, MessageKey> = { baseline_only: "plan.note.baseline_only", engine_not_implemented: "plan.note.engine_not_implemented" };
const OUTCOME_KEY: Record<string, MessageKey> = { enqueued: "search.enqueued", deduplicated: "search.deduplicated", cache_hit: "search.cacheHit" };

type Edits = { query: string; country: string; language: string; location: string; target_domain: string; compare_previous: boolean; only_new: boolean };

export function editsFrom(plan: IntentPlan): Edits {
  const fields = plan.plan ?? {};
  return {
    query: fields.query ?? "", country: fields.country ?? "", language: fields.language ?? "", location: fields.location ?? "",
    target_domain: fields.target_domain ?? "", compare_previous: fields.compare_previous ?? false, only_new: fields.only_new ?? false,
  };
}

/** What is sent when confirming: edited fields only, blanks left out so the API reports them as missing. */
export function confirmPayload(edits: Edits): Record<string, string | boolean> {
  const payload: Record<string, string | boolean> = { compare_previous: edits.compare_previous, only_new: edits.only_new };
  for (const key of ["query", "country", "language", "location", "target_domain"] as const) {
    const value = edits[key].trim();
    if (value) payload[key] = value;
  }
  return payload;
}

export function sourceLabel(t: Translate, field: FieldProvenance | undefined): string | null {
  if (!field) return null;
  if (field.source === "laya") return t("plan.source.laya", { confidence: field.confidence !== undefined ? formatPercent(field.confidence, "en") : "" });
  if (field.source === "rule") {
    if (field.derived_from) return t("plan.source.derived", { from: field.derived_from });
    // A flag found by a word list has no single piece of evidence to quote.
    return field.evidence ? t("plan.source.rule", { evidence: field.evidence }) : t("plan.source.cue");
  }
  if (field.source === "missing") return t("plan.source.missing");
  return t("plan.source.default");
}

export function prefillHref(prefill: Record<string, string | undefined> | undefined): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(prefill ?? {})) if (value) params.set(key, value);
  const query = params.toString();
  return query ? `/keywords?${query}` : "/keywords";
}

function Fallback({ plan }: { plan: IntentPlan }) {
  const { t } = useLocale();
  return (
    <div className="mt-4 rounded-md border border-border bg-bg p-3 text-sm">
      <p>{t("plan.fallbackIntro")}</p>
      <Link href={prefillHref(plan.structured_input?.prefill)} className="mt-2 inline-block"><Button variant="primary">{t("plan.openKeywordForm")}</Button></Link>
      {plan.structured_input && Object.keys(plan.structured_input.prefill).length > 0 && (
        <p className="mt-2 text-xs text-muted">{t("plan.prefillNote")}</p>
      )}
    </div>
  );
}

function ClassifierDetails({ plan }: { plan: IntentPlan }) {
  const { t, locale } = useLocale();
  const c = plan.classifier;
  if (!c.enabled || !c.intent) return null;
  return (
    <details className="mt-4 text-sm">
      <summary className="cursor-pointer text-muted">{t("plan.classifier")}</summary>
      <dl className="mt-2 grid gap-1 sm:grid-cols-2">
        <div className="flex gap-2"><dt className="text-muted">{t("plan.classifierIntent")}</dt><dd>{t(INTENT_KEY[c.intent] ?? "intent.unsupported")} ({formatPercent(c.confidence ?? null, locale)})</dd></div>
        <div className="flex gap-2"><dt className="text-muted">{t("plan.classifierThreshold")}</dt><dd>{formatPercent(c.min_confidence ?? null, locale)}</dd></div>
        <div className="flex gap-2"><dt className="text-muted">{t("plan.classifierVersion")}</dt><dd className="break-all">{c.version}</dd></div>
        <div className="flex gap-2"><dt className="text-muted">{t("plan.classifierLatency")}</dt><dd>{c.latency_ms !== undefined ? `${c.latency_ms} ms` : "—"}</dd></div>
      </dl>
      {c.probabilities && (
        <ul className="mt-2 flex flex-wrap gap-x-4 text-xs text-muted">
          {Object.entries(c.probabilities).map(([intent, probability]) => <li key={intent}>{t(INTENT_KEY[intent] ?? "intent.unsupported")}: {formatPercent(probability, locale)}</li>)}
        </ul>
      )}
    </details>
  );
}

function Executed({ plan }: { plan: IntentPlan }) {
  const { t } = useLocale();
  const execution = plan.execution;
  if (!execution) return null;
  if (execution.kind === "history") {
    return (
      <div role="status" className="rounded-md border border-ok bg-ok-bg p-3 text-sm text-ok">
        <p className="font-semibold"><span aria-hidden="true">✓ </span>{t("plan.executedHistory")}</p>
        <Link href={execution.keyword_id ? `/keywords/${execution.keyword_id}` : "/keywords"} className="mt-2 inline-block underline">{t("plan.openHistory")}</Link>
      </div>
    );
  }
  return (
    <div role="status" className="rounded-md border border-ok bg-ok-bg p-3 text-sm text-ok">
      <p className="font-semibold"><span aria-hidden="true">✓ </span>{t(OUTCOME_KEY[execution.search_outcome] ?? "search.enqueued")}</p>
      <p className="mt-1">{execution.keyword_created ? t("plan.keywordCreated") : t("plan.keywordReused")}</p>
      <Link href={`/keywords/${execution.keyword_id}`} className="mt-2 inline-block font-medium underline">{t("plan.openKeyword")}</Link>
    </div>
  );
}

export function PlanResult({ plan, options, onUpdated }: { plan: IntentPlan; options: Options | undefined; onUpdated: (plan: IntentPlan) => void }) {
  const { t, locale } = useLocale();
  const toast = useToast();
  const revalidate = useRevalidateAll();
  const [edits, setEdits] = useState<Edits>(() => editsFrom(plan));
  const [busy, setBusy] = useState(false);
  const [confirmError, setConfirmError] = useState<unknown>(null);

  const intent = plan.plan?.intent;
  const reasonKey = plan.reason ? REASON_KEY[plan.reason] : undefined;
  const editable = intent === "organic_rank_tracking" && plan.status !== "executed" && (plan.status === "ready" || plan.next_step === "complete_fields");
  const ready = plan.status === "ready";
  const complete = edits.query.trim() && edits.country && edits.language && edits.target_domain.trim();

  const set = <K extends keyof Edits>(key: K, value: Edits[K]) => setEdits((current) => ({ ...current, [key]: value }));
  const missing = (field: string) => plan.missing.includes(field) && !String(edits[field as keyof Edits] ?? "").trim();

  async function confirm() {
    setBusy(true);
    setConfirmError(null);
    try {
      const response = await api.post<{ data: IntentPlan }>(`/api/v1/intent/plan/${plan.id}/confirm`, { plan: confirmPayload(edits) });
      onUpdated(response.data);
      toast.push(t("plan.confirmed"), "success");
      await revalidate();
    } catch (error) {
      setConfirmError(error);
    } finally {
      setBusy(false);
    }
  }

  const tone = plan.status === "ready" || plan.status === "executed" ? "ok" : plan.status === "unavailable" ? "neutral" : plan.status === "unsupported" ? "danger" : "warn";
  const statusKey: MessageKey = `plan.status.${plan.status}`;
  const detailErrors = confirmError instanceof ApiError && confirmError.code === "invalid_plan" ? (confirmError.details as { errors?: Record<string, string>; missing?: string[] } | null) : null;

  return (
    <Card title={t("plan.title")}>
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={tone} icon={plan.status === "ready" || plan.status === "executed" ? "check" : plan.status === "unsupported" ? "cross" : plan.status === "unavailable" ? "circle" : "info"}>{t(statusKey)}</Badge>
        {intent && <Badge tone="info">{t(INTENT_KEY[intent] ?? "intent.unsupported")}</Badge>}
      </div>
      <p className="mt-3 text-sm" aria-live="polite">{reasonKey ? t(reasonKey) : plan.status === "ready" ? t("plan.readyIntro") : plan.status === "executed" ? t("plan.executedIntro") : ""}</p>

      {plan.status === "needs_clarification" && plan.reason === "low_confidence" && plan.candidates.length > 0 && (
        <div className="mt-3">
          <p className="text-sm font-medium">{t("plan.candidates")}</p>
          <ul className="mt-1 list-inside list-disc text-sm">
            {plan.candidates.map((candidate) => <li key={candidate.intent}>{t(INTENT_KEY[candidate.intent] ?? "intent.unsupported")} ({formatPercent(candidate.probability, locale)})</li>)}
          </ul>
        </div>
      )}

      {plan.keyword_candidates.length > 0 && (
        <ul className="mt-3 list-inside list-disc text-sm">
          {plan.keyword_candidates.map((candidate) => (
            <li key={candidate.id}><Link href={`/keywords/${candidate.id}`} className="text-accent underline">{candidate.query}</Link>{candidate.target_domain ? ` (${candidate.target_domain})` : ""}</li>
          ))}
        </ul>
      )}

      {plan.notes.map((note) => (NOTE_KEY[note] ? <p key={note} className="mt-3 rounded-md border border-info bg-info-bg p-2 text-sm text-info"><span aria-hidden="true">ℹ </span>{t(NOTE_KEY[note])}</p> : null))}

      {editable && (
        <form onSubmit={(event) => { event.preventDefault(); if (complete) void confirm(); }} className="mt-4 grid gap-4 sm:grid-cols-2" noValidate>
          <div className="sm:col-span-2">
            <Field label={t("planField.query")} required error={missing("query") ? t("plan.fillIn") : null} hint={missing("query") ? undefined : sourceLabel(t, plan.fields.query) ?? undefined}>
              {(props) => <input {...props} className={INPUT_CLASS} value={edits.query} onChange={(event) => set("query", event.target.value)} />}
            </Field>
            {plan.query_suggestions.length > 0 && !edits.query && (
              <p className="mt-1 text-xs text-muted">{t("plan.suggestions")}{" "}
                {plan.query_suggestions.map((suggestion) => <button key={suggestion} type="button" className="mr-2 underline" onClick={() => set("query", suggestion)}>{suggestion}</button>)}
              </p>
            )}
          </div>
          <Field label={t("planField.target_domain")} required error={missing("target_domain") ? t("plan.fillIn") : null} hint={missing("target_domain") ? undefined : sourceLabel(t, plan.fields.target_domain) ?? undefined}>
            {(props) => <input {...props} className={INPUT_CLASS} value={edits.target_domain} onChange={(event) => set("target_domain", event.target.value)} placeholder="example.com" />}
          </Field>
          <Field label={t("planField.country")} required error={missing("country") ? t("plan.fillIn") : null} hint={missing("country") ? undefined : sourceLabel(t, plan.fields.country) ?? undefined}>
            {(props) => (
              <select {...props} className={INPUT_CLASS} value={edits.country} onChange={(event) => set("country", event.target.value)}>
                <option value="">—</option>
                {(options?.countries ?? []).map((code) => <option key={code} value={code}>{countryName(code, locale)} ({code})</option>)}
              </select>
            )}
          </Field>
          <Field label={t("planField.language")} required error={missing("language") ? t("plan.fillIn") : null} hint={missing("language") ? undefined : sourceLabel(t, plan.fields.language) ?? undefined}>
            {(props) => (
              <select {...props} className={INPUT_CLASS} value={edits.language} onChange={(event) => set("language", event.target.value)}>
                <option value="">—</option>
                {(options?.languages ?? []).map((code) => <option key={code} value={code}>{languageName(code, locale)} ({code})</option>)}
              </select>
            )}
          </Field>
          <fieldset className="sm:col-span-2">
            <legend className="text-sm font-medium">{t("plan.options")}</legend>
            <div className="mt-1 flex flex-wrap gap-x-6 gap-y-1 text-sm">
              <label className="flex items-center gap-2"><input type="checkbox" className="size-4 accent-accent" checked={edits.compare_previous} onChange={(event) => set("compare_previous", event.target.checked)} />{t("plan.compare")} <span className="text-xs text-muted">({sourceLabel(t, plan.fields.compare_previous)})</span></label>
              <label className="flex items-center gap-2"><input type="checkbox" className="size-4 accent-accent" checked={edits.only_new} onChange={(event) => set("only_new", event.target.checked)} />{t("plan.onlyNew")} <span className="text-xs text-muted">({sourceLabel(t, plan.fields.only_new)})</span></label>
            </div>
          </fieldset>
          <div className="sm:col-span-2">
            <p className="mb-2 text-sm text-muted">{t("plan.confirmCost")}</p>
            <Button type="submit" variant="primary" disabled={busy || !complete}>{busy ? t("common.saving") : ready ? t("plan.confirm") : t("plan.completeAndConfirm")}</Button>
            {!complete && <p className="mt-1 text-xs text-muted">{t("plan.needAll")}</p>}
          </div>
        </form>
      )}

      {!editable && plan.plan && plan.status !== "executed" && intent !== "search_history" && (
        <dl className="mt-4 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
          {(["query", "country", "language", "target_domain"] as const).map((field) => plan.plan?.[field] ? (
            <div key={field} className="flex gap-2"><dt className="text-muted">{t(`planField.${field}` as MessageKey)}</dt><dd>{plan.plan[field]}</dd></div>
          ) : null)}
        </dl>
      )}

      {intent === "search_history" && ready && (
        <div className="mt-4">
          <Link href={plan.plan?.keyword_id ? `/keywords/${plan.plan.keyword_id}` : "/keywords"}><Button variant="primary">{t("plan.openHistory")}</Button></Link>
          <p className="mt-2 text-xs text-muted">{t("plan.historyReadOnly")}</p>
        </div>
      )}

      {confirmError != null && (
        <div className="mt-4">
          <ErrorState error={confirmError} />
          {detailErrors && (
            <ul className="mt-2 list-inside list-disc text-sm text-danger">
              {Object.entries(detailErrors.errors ?? {}).map(([field, code]) => <li key={field}>{field}: {code}</li>)}
              {(detailErrors.missing ?? []).map((field) => <li key={field}>{field}: {t("plan.missingField")}</li>)}
            </ul>
          )}
          {confirmError instanceof ApiError && !["invalid_plan"].includes(confirmError.code) && <p className="sr-only">{describeError(confirmError, t).title}</p>}
        </div>
      )}

      {plan.status === "executed" && <div className="mt-4"><Executed plan={plan} /></div>}
      {(plan.next_step === "rephrase_or_use_structured_input" || plan.next_step === "use_structured_input") && <Fallback plan={plan} />}
      <ClassifierDetails plan={plan} />
    </Card>
  );
}
