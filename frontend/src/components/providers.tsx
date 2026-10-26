"use client";

import type { ReactNode } from "react";
import { SWRConfig } from "swr";
import { fetcher } from "@/lib/api";
import type { Locale } from "@/lib/i18n";
import { LocaleProvider } from "./locale";
import { ToastProvider } from "./toast";

export function Providers({ locale, children }: { locale: Locale; children: ReactNode }) {
  return (
    <LocaleProvider initial={locale}>
      <SWRConfig
        value={{
          fetcher,
          // A 4xx will not fix itself, and a down server should show an error with a retry button
          // rather than hammer the API in the background.
          shouldRetryOnError: false,
          revalidateOnFocus: true,
          dedupingInterval: 2000,
        }}
      >
        <ToastProvider>{children}</ToastProvider>
      </SWRConfig>
    </LocaleProvider>
  );
}
