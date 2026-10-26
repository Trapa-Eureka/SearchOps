"use client";

import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";
import { LOCALE_COOKIE, translate, type Locale, type Translate } from "@/lib/i18n";

type LocaleContextValue = { locale: Locale; setLocale: (locale: Locale) => void; t: Translate };

const LocaleContext = createContext<LocaleContextValue | null>(null);

export function LocaleProvider({ initial, children }: { initial: Locale; children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(initial);

  const setLocale = useCallback((next: Locale) => {
    setLocaleState(next);
    document.cookie = `${LOCALE_COOKIE}=${next}; path=/; max-age=31536000; samesite=lax`;
    document.documentElement.lang = next;
  }, []);

  const value = useMemo<LocaleContextValue>(
    () => ({ locale, setLocale, t: (key, vars) => translate(locale, key, vars) }),
    [locale, setLocale],
  );
  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}

export function useLocale(): LocaleContextValue {
  const value = useContext(LocaleContext);
  if (!value) throw new Error("useLocale must be used inside <LocaleProvider>");
  return value;
}

export function useT(): Translate {
  return useLocale().t;
}
