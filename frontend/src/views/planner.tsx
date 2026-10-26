"use client";

import { useState, type FormEvent } from "react";
import { PlanResult } from "@/components/plan-result";
import { useLocale } from "@/components/locale";
import { Badge, Button, Card, ErrorState, INPUT_CLASS, PageTitle } from "@/components/ui";
import { useOptions } from "@/hooks/api";
import { api } from "@/lib/api";
import type { MessageKey } from "@/lib/i18n";
import type { IntentPlan } from "@/lib/types";

const EXAMPLES: MessageKey[] = ["planner.example1", "planner.example2", "planner.example3"];

export function PlannerView() {
  const { t } = useLocale();
  const options = useOptions();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [plan, setPlan] = useState<IntentPlan | null>(null);

  const max = options.data?.data.limits.intent_text_max_length ?? 500;
  const enabled = options.data?.data.features.intent_planning;
  const tooLong = text.length > max;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!text.trim() || tooLong) return;
    setBusy(true);
    setError(null);
    try {
      const response = await api.post<{ data: IntentPlan }>("/api/v1/intent/plan", { text });
      setPlan(response.data);
    } catch (caught) {
      setPlan(null);
      setError(caught);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageTitle title={t("planner.title")}>
        {enabled !== undefined && (
          <Badge tone={enabled ? "ok" : "neutral"} icon={enabled ? "●" : "○"}>{enabled ? t("planner.on") : t("planner.off")}</Badge>
        )}
      </PageTitle>
      <p className="mb-4 max-w-3xl text-sm text-muted">{t("planner.intro")}</p>
      {enabled === false && (
        <p className="mb-4 rounded-md border border-border bg-bg p-3 text-sm"><span aria-hidden="true">ℹ </span>{t("planner.offNote")}</p>
      )}

      <Card>
        <form onSubmit={submit} className="grid gap-3">
          <label htmlFor="planner-text" className="text-sm font-medium">{t("planner.label")}</label>
          <textarea
            id="planner-text"
            rows={3}
            value={text}
            onChange={(event) => setText(event.target.value)}
            aria-invalid={tooLong}
            aria-describedby="planner-count"
            className={INPUT_CLASS}
            placeholder={t("planner.placeholder")}
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p id="planner-count" className={tooLong ? "text-xs font-medium text-danger" : "text-xs text-muted"}>{t("planner.counter", { count: text.length, max })}</p>
            <Button type="submit" variant="primary" disabled={busy || !text.trim() || tooLong}>{busy ? t("planner.reading") : t("planner.submit")}</Button>
          </div>
          <div className="text-sm">
            <p className="text-muted">{t("planner.tryExample")}</p>
            <ul className="mt-1 flex flex-wrap gap-2">
              {EXAMPLES.map((key) => (
                <li key={key}><button type="button" className="rounded-full border border-border px-3 py-1 text-left hover:bg-bg focus-visible:outline-2 focus-visible:outline-accent" onClick={() => setText(t(key))}>{t(key)}</button></li>
              ))}
            </ul>
          </div>
        </form>
      </Card>

      {error != null && <div className="mt-5"><ErrorState error={error} /></div>}
      {plan && <div className="mt-5"><PlanResult key={plan.id} plan={plan} options={options.data?.data} onUpdated={setPlan} /></div>}
    </>
  );
}
