"use client";

import { useMemo, useRef, useState, type FormEvent } from "react";
import { ApiError } from "@/lib/api";
import { countryName, languageName } from "@/lib/format";
import type { MessageKey } from "@/lib/i18n";
import type { Keyword, KeywordInput, Options, Schedule } from "@/lib/types";
import { useLocale, useT } from "./locale";
import { Button, Field, INPUT_CLASS } from "./ui";

export type KeywordFormValues = {
  query: string; country: string; language: string; location: string; target_domain: string; schedule: Schedule; active: boolean;
};

export function valuesFromKeyword(keyword: Keyword): KeywordFormValues {
  return {
    query: keyword.query, country: keyword.country, language: keyword.language, location: keyword.location ?? "",
    target_domain: keyword.target_domain ?? "", schedule: keyword.schedule, active: keyword.active,
  };
}

export const EMPTY_VALUES: KeywordFormValues = { query: "", country: "us", language: "en", location: "", target_domain: "", schedule: "manual", active: true };

/** Checks the same limits the API enforces so most mistakes are caught before a request is sent. */
export function validateKeyword(values: KeywordFormValues, options: Options): Partial<Record<keyof KeywordFormValues, MessageKey>> {
  const errors: Partial<Record<keyof KeywordFormValues, MessageKey>> = {};
  const query = values.query.replace(/\s+/g, " ").trim();
  if (!query) errors.query = "form.errorRequired";
  else if (query.length > options.limits.query_max_length) errors.query = "form.errorTooLong";
  if (!options.countries.includes(values.country)) errors.country = "form.errorChoose";
  if (!options.languages.includes(values.language)) errors.language = "form.errorChoose";
  if (values.location.trim().length > options.limits.location_max_length) errors.location = "form.errorTooLong";
  return errors;
}

export function toPayload(values: KeywordFormValues): KeywordInput {
  return {
    query: values.query,
    country: values.country,
    language: values.language,
    location: values.location.trim() || null,
    target_domain: values.target_domain.trim() || null,
    schedule: values.schedule,
    active: values.active,
  };
}

export function KeywordForm({ options, initial = EMPTY_VALUES, submitLabel, onSubmit, onCancel }: {
  options: Options; initial?: KeywordFormValues; submitLabel: string; onSubmit: (payload: KeywordInput) => Promise<void>; onCancel?: () => void;
}) {
  const t = useT();
  const { locale } = useLocale();
  const [values, setValues] = useState<KeywordFormValues>(initial);
  const [submitted, setSubmitted] = useState(false);
  const [serverErrors, setServerErrors] = useState<Record<string, string[]>>({});
  const [fatal, setFatal] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const summaryRef = useRef<HTMLDivElement>(null);

  const clientErrors = useMemo(() => (submitted ? validateKeyword(values, options) : {}), [submitted, values, options]);
  const countries = useMemo(() => [...options.countries].sort((a, b) => countryName(a, locale).localeCompare(countryName(b, locale), locale)), [options.countries, locale]);
  const languages = useMemo(() => [...options.languages].sort((a, b) => languageName(a, locale).localeCompare(languageName(b, locale), locale)), [options.languages, locale]);

  const set = <K extends keyof KeywordFormValues>(key: K, value: KeywordFormValues[K]) => {
    setValues((current) => ({ ...current, [key]: value }));
    setServerErrors((current) => (key in current ? Object.fromEntries(Object.entries(current).filter(([field]) => field !== key)) : current));
  };

  const errorFor = (field: keyof KeywordFormValues): string | null => {
    const client = clientErrors[field];
    if (client) return t(client, { max: field === "query" ? options.limits.query_max_length : options.limits.location_max_length });
    return serverErrors[field]?.[0] ?? null;
  };

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setSubmitted(true);
    setFatal(null);
    if (Object.keys(validateKeyword(values, options)).length > 0) {
      window.setTimeout(() => summaryRef.current?.focus(), 0);
      return;
    }
    setBusy(true);
    try {
      await onSubmit(toPayload(values));
    } catch (error) {
      if (error instanceof ApiError && error.code === "validation_failed") setServerErrors(error.fieldErrors);
      else setFatal(error instanceof ApiError ? error.message : t("error.unexpected"));
      window.setTimeout(() => summaryRef.current?.focus(), 0);
    } finally {
      setBusy(false);
    }
  }

  const baseErrors = serverErrors.base ?? [];
  const fieldLabels: Record<string, string> = {
    query: t("form.query"), country: t("form.country"), language: t("form.language"), location: t("form.location"),
    target_domain: t("form.targetDomain"), schedule: t("form.schedule"), engine: t("form.country"), active: t("form.active"),
  };
  const fields = [...new Set([...Object.keys(clientErrors), ...Object.keys(serverErrors).filter((field) => field !== "base")])] as (keyof KeywordFormValues)[];
  const summaryItems = fields.map((field) => `${fieldLabels[field] ?? field}: ${errorFor(field) ?? ""}`);

  return (
    <form onSubmit={handleSubmit} noValidate className="grid gap-4 sm:grid-cols-2">
      {(summaryItems.length > 0 || baseErrors.length > 0 || fatal) && (
        <div ref={summaryRef} tabIndex={-1} role="alert" className="rounded-md border border-danger bg-danger-bg p-3 text-sm text-danger focus:outline-2 focus:outline-danger sm:col-span-2">
          <p className="font-semibold">{t("form.fixErrors")}</p>
          <ul className="mt-1 list-inside list-disc">
            {baseErrors.map((message) => <li key={message}>{message}</li>)}
            {summaryItems.map((item) => <li key={item}>{item}</li>)}
            {fatal && <li>{fatal}</li>}
          </ul>
        </div>
      )}

      <div className="sm:col-span-2">
        <Field label={t("form.query")} required error={errorFor("query")} hint={t("form.queryHint", { max: options.limits.query_max_length })}>
          {(props) => <input {...props} className={INPUT_CLASS} value={values.query} maxLength={options.limits.query_max_length + 50} onChange={(event) => set("query", event.target.value)} autoComplete="off" />}
        </Field>
      </div>

      <Field label={t("form.country")} required error={errorFor("country")}>
        {(props) => (
          <select {...props} className={INPUT_CLASS} value={values.country} onChange={(event) => set("country", event.target.value)}>
            {countries.map((code) => <option key={code} value={code}>{countryName(code, locale)} ({code})</option>)}
          </select>
        )}
      </Field>

      <Field label={t("form.language")} required error={errorFor("language")} hint={t("form.languageHint")}>
        {(props) => (
          <select {...props} className={INPUT_CLASS} value={values.language} onChange={(event) => set("language", event.target.value)}>
            {languages.map((code) => <option key={code} value={code}>{languageName(code, locale)} ({code})</option>)}
          </select>
        )}
      </Field>

      <Field label={t("form.location")} error={errorFor("location")} hint={t("form.locationHint")}>
        {(props) => <input {...props} className={INPUT_CLASS} value={values.location} onChange={(event) => set("location", event.target.value)} autoComplete="off" />}
      </Field>

      <Field label={t("form.targetDomain")} error={errorFor("target_domain")} hint={t("form.targetDomainHint")}>
        {(props) => <input {...props} className={INPUT_CLASS} value={values.target_domain} onChange={(event) => set("target_domain", event.target.value)} placeholder="example.com" autoComplete="off" inputMode="url" />}
      </Field>

      <Field label={t("form.schedule")} error={errorFor("schedule")} hint={t("form.scheduleHint")}>
        {(props) => (
          <select {...props} className={INPUT_CLASS} value={values.schedule} onChange={(event) => set("schedule", event.target.value as Schedule)}>
            {options.schedules.map((schedule) => <option key={schedule} value={schedule}>{t(`schedule.${schedule}` as MessageKey)}</option>)}
          </select>
        )}
      </Field>

      <div className="flex items-end">
        <label className="flex items-center gap-2 text-sm font-medium">
          <input type="checkbox" className="size-4 accent-accent" checked={values.active} onChange={(event) => set("active", event.target.checked)} />
          {t("form.active")}
        </label>
      </div>

      <div className="flex flex-wrap gap-2 sm:col-span-2">
        <Button type="submit" variant="primary" disabled={busy}>{busy ? t("common.saving") : submitLabel}</Button>
        {onCancel && <Button onClick={onCancel} disabled={busy}>{t("common.cancel")}</Button>}
      </div>
    </form>
  );
}
