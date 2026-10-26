"use client";

import { Button } from "@/components/ui";
import { useT } from "@/components/locale";

export default function GlobalError({ reset }: { error: Error; reset: () => void }) {
  const t = useT();
  return (
    <div role="alert" className="py-16 text-center">
      <h1 className="text-xl font-semibold">{t("error.unexpected")}</h1>
      <Button className="mt-4" variant="primary" onClick={reset}>{t("common.retry")}</Button>
    </div>
  );
}
