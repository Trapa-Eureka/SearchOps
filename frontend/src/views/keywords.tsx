"use client";

import { useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import { useLocale } from "@/components/locale";
import { EMPTY_VALUES, KeywordForm, type KeywordFormValues } from "@/components/keyword-form";
import { KeywordsTable } from "@/components/tables";
import { useToast } from "@/components/toast";
import { Button, Card, EmptyState, ErrorState, Loading, PageTitle, Pagination } from "@/components/ui";
import { useStartSearch } from "@/hooks/actions";
import { useKeywords, useOptions, useRevalidateAll } from "@/hooks/api";
import { api } from "@/lib/api";
import { describeError } from "@/lib/errors";
import type { Keyword, KeywordInput } from "@/lib/types";

/** Values handed over from the planner's fallback. They only prefill the form; the API validates them again. */
function prefillFrom(params: URLSearchParams, countries: string[], languages: string[]): KeywordFormValues | null {
  const query = params.get("query");
  const country = params.get("country");
  const language = params.get("language");
  const domain = params.get("target_domain");
  if (!query && !country && !language && !domain) return null;
  return {
    ...EMPTY_VALUES,
    query: (query ?? "").slice(0, 200),
    country: country && countries.includes(country) ? country : EMPTY_VALUES.country,
    language: language && languages.includes(language) ? language : EMPTY_VALUES.language,
    target_domain: (domain ?? "").slice(0, 253),
  };
}

export function KeywordsView() {
  const { t } = useLocale();
  const toast = useToast();
  const params = useSearchParams();
  const startSearch = useStartSearch();
  const revalidate = useRevalidateAll();
  const [page, setPage] = useState(1);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [formOpen, setFormOpen] = useState<boolean | null>(null);

  const options = useOptions();
  const keywords = useKeywords(page);
  const prefill = useMemo(
    () => (options.data ? prefillFrom(params, options.data.data.countries, options.data.data.languages) : null),
    [params, options.data],
  );
  const open = formOpen ?? (prefill !== null || keywords.data?.meta.total_count === 0);

  async function create(payload: KeywordInput) {
    await api.post("/api/v1/keywords", { keyword: payload });
    toast.push(t("keywords.created"), "success");
    setFormOpen(false);
    await revalidate();
  }

  async function toggleActive(keyword: Keyword) {
    setBusyId(keyword.id);
    try {
      await api.patch(`/api/v1/keywords/${keyword.id}`, { keyword: { active: !keyword.active } });
      toast.push(keyword.active ? t("keywords.paused") : t("keywords.resumed"), "success");
      await revalidate();
    } catch (error) {
      toast.push(describeError(error, t).title, "error");
    } finally {
      setBusyId(null);
    }
  }

  async function search(keyword: Keyword) {
    setBusyId(keyword.id);
    await startSearch(keyword.id);
    setBusyId(null);
  }

  const limits = options.data?.data.limits;
  const total = keywords.data?.meta.total_count;

  return (
    <>
      <PageTitle title={t("keywords.title")} description={t("keywords.description")}>
        {limits && total !== undefined && t("keywords.count", { count: total, max: limits.max_keywords })}
      </PageTitle>

      <Card
        icon="plus"
        title={t("keywords.addTitle")}
        actions={<Button aria-expanded={open} icon={open ? undefined : "plus"} onClick={() => setFormOpen(!open)}>{open ? t("common.close") : t("keywords.add")}</Button>}
        className="mb-5"
      >
        {!open && <p className="text-sm text-muted">{t("keywords.addHint")}</p>}
        {open && options.error && <ErrorState error={options.error} onRetry={() => options.mutate()} />}
        {open && !options.data && !options.error && <Loading />}
        {open && options.data && (
          <KeywordForm
            key={prefill ? "prefilled" : "blank"}
            options={options.data.data}
            initial={prefill ?? EMPTY_VALUES}
            submitLabel={t("keywords.create")}
            onSubmit={create}
            onCancel={() => setFormOpen(false)}
          />
        )}
      </Card>

      <Card icon="search" title={t("keywords.list")}>
        {keywords.error && <ErrorState error={keywords.error} onRetry={() => keywords.mutate()} />}
        {!keywords.data && !keywords.error && <Loading />}
        {keywords.data && keywords.data.data.length === 0 && (
          <EmptyState title={t("keywords.emptyTitle")}>{t("keywords.emptyBody")}</EmptyState>
        )}
        {keywords.data && keywords.data.data.length > 0 && (
          <>
            <KeywordsTable keywords={keywords.data.data} onToggleActive={toggleActive} onSearch={search} busyId={busyId} />
            <Pagination meta={keywords.data.meta} onPage={setPage} />
          </>
        )}
      </Card>
    </>
  );
}
