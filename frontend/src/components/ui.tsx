"use client";

import { useEffect, useId, useRef, type ButtonHTMLAttributes, type ReactNode } from "react";
import { ApiError } from "@/lib/api";
import { describeError } from "@/lib/errors";
import type { PageMeta } from "@/lib/types";
import { formatNumber } from "@/lib/format";
import { Icon, type IconName } from "./icons";
import { useLocale, useT } from "./locale";

export function cx(...parts: (string | false | null | undefined)[]): string {
  return parts.filter(Boolean).join(" ");
}

const FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & { variant?: "primary" | "secondary" | "danger" | "ghost"; size?: "md" | "sm"; icon?: IconName };
const BUTTON_VARIANT = {
  primary: "bg-accent text-accent-contrast hover:bg-accent-hover border-transparent shadow-sm",
  secondary: "bg-surface text-text border-border hover:bg-surface-2 shadow-sm",
  danger: "bg-danger text-white border-transparent hover:opacity-90",
  ghost: "bg-transparent text-accent border-transparent hover:bg-surface-2",
} as const;

export function Button({ variant = "secondary", size = "md", icon, className, type = "button", children, ...props }: ButtonProps) {
  return (
    <button
      type={type}
      {...props}
      className={cx(
        "inline-flex items-center justify-center gap-2 rounded-lg border font-medium disabled:cursor-not-allowed disabled:opacity-50",
        size === "md" ? "px-3.5 py-2 text-sm" : "px-2.5 py-1 text-xs",
        BUTTON_VARIANT[variant],
        FOCUS,
        className,
      )}
    >
      {icon && <Icon name={icon} className={size === "md" ? "size-4" : "size-3.5"} />}
      {children}
    </button>
  );
}

export function Card({ title, description, icon, actions, children, className, id }: {
  title?: ReactNode; description?: ReactNode; icon?: IconName; actions?: ReactNode; children: ReactNode; className?: string; id?: string;
}) {
  const headingId = useId();
  return (
    <section aria-labelledby={title ? headingId : undefined} id={id} className={cx("min-w-0 rounded-xl bg-surface p-4 shadow-card sm:p-5", className)}>
      {(title || actions) && (
        <div className="mb-4 flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
          <div className="flex min-w-0 items-center gap-3">
            {icon && <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-info-bg text-info"><Icon name={icon} /></span>}
            <div className="min-w-0">
              {title && <h2 id={headingId} className="text-[0.95rem] font-semibold leading-tight">{title}</h2>}
              {description && <p className="mt-0.5 text-xs text-muted">{description}</p>}
            </div>
          </div>
          {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  );
}

export type Tone = "ok" | "warn" | "danger" | "info" | "neutral";
const BADGE_TONE: Record<Tone, string> = {
  ok: "bg-ok-bg text-ok",
  warn: "bg-warn-bg text-warn",
  danger: "bg-danger-bg text-danger",
  info: "bg-info-bg text-info",
  neutral: "bg-surface-2 text-muted ring-1 ring-inset ring-border",
};

/** Status is never conveyed by colour alone: every badge carries an icon and a word. */
export function Badge({ tone = "neutral", icon, children, title }: { tone?: Tone; icon?: IconName; children: ReactNode; title?: string }) {
  return (
    <span title={title} className={cx("inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-medium", BADGE_TONE[tone])}>
      {icon && <Icon name={icon} className="size-3.5" />}
      {children}
    </span>
  );
}

const TILE_TONE: Record<Tone, string> = {
  ok: "bg-ok-bg text-ok", warn: "bg-warn-bg text-warn", danger: "bg-danger-bg text-danger", info: "bg-info-bg text-info", neutral: "bg-surface-2 text-muted",
};

/** One headline number: an icon tile, a label, a large value, and a line of context. Use inside a <dl>. */
export function Metric({ label, value, hint, tone = "neutral", icon, iconTone = "info" }: {
  label: string; value: ReactNode; hint?: ReactNode; tone?: Tone; icon?: IconName; iconTone?: Tone;
}) {
  return (
    <div className="min-w-0 rounded-xl bg-surface p-4 shadow-card">
      <dt className="flex items-center gap-2.5 text-sm font-medium text-muted">
        {icon && <span className={cx("flex size-8 shrink-0 items-center justify-center rounded-lg", TILE_TONE[iconTone])}><Icon name={icon} /></span>}
        <span className="min-w-0">{label}</span>
      </dt>
      <dd className="mt-3 text-[1.65rem] font-semibold leading-none tracking-tight tabular-nums">{value}</dd>
      {hint && <dd className={cx("mt-2 text-xs", tone === "warn" ? "text-warn" : tone === "danger" ? "text-danger" : "text-muted")}>{hint}</dd>}
    </div>
  );
}

/** A row of options that act as a filter: one is pressed. Counts are shown when given. */
export function Segmented<T extends string>({ label, value, options, onChange }: {
  label: string; value: T; options: { value: T; label: string; count?: number }[]; onChange: (value: T) => void;
}) {
  const { locale } = useLocale();
  return (
    <div role="group" aria-label={label} className="inline-flex max-w-full flex-wrap gap-1 rounded-xl bg-surface-2 p-1 ring-1 ring-inset ring-border">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          aria-pressed={value === option.value}
          onClick={() => onChange(option.value)}
          className={cx(
            "flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium",
            FOCUS,
            value === option.value ? "bg-surface text-text shadow-sm ring-1 ring-border" : "text-muted hover:text-text",
          )}
        >
          {option.label}{" "}
          {option.count !== undefined && <span className="text-xs tabular-nums opacity-80">{formatNumber(option.count, locale)}</span>}
        </button>
      ))}
    </div>
  );
}

export function Loading({ label }: { label?: string }) {
  const t = useT();
  return (
    <div role="status" className="flex items-center gap-2 py-6 text-sm text-muted">
      <span aria-hidden="true" className="inline-block size-4 animate-spin rounded-full border-2 border-border border-t-accent" />
      {label ?? t("common.loading")}
    </div>
  );
}

export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const t = useT();
  const { title, detail } = describeError(error, t);
  return (
    <div role="alert" className="rounded-xl border border-danger bg-danger-bg p-4 text-sm text-danger">
      <p className="font-semibold"><span aria-hidden="true">✕ </span>{title}</p>
      {detail && <p className="mt-1">{detail}</p>}
      {error instanceof ApiError && error.code !== "validation_failed" && error.message && (
        <p className="mt-1 text-xs opacity-80">{error.message}</p>
      )}
      {onRetry && <Button className="mt-3" size="sm" onClick={onRetry}>{t("common.retry")}</Button>}
    </div>
  );
}

export function EmptyState({ title, children, action }: { title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-border-strong p-6 text-center">
      <p className="font-medium">{title}</p>
      {children && <p className="mx-auto mt-1 max-w-prose text-sm text-muted">{children}</p>}
      {action && <div className="mt-3">{action}</div>}
    </div>
  );
}

type FieldRenderProps = { id: string; "aria-invalid": boolean; "aria-describedby": string | undefined };

export function Field({ label, error, hint, required, children }: { label: string; error?: string | null; hint?: string; required?: boolean; children: (props: FieldRenderProps) => ReactNode }) {
  const id = useId();
  const hintId = hint ? `${id}-hint` : undefined;
  const errorId = error ? `${id}-error` : undefined;
  const describedBy = [errorId, hintId].filter(Boolean).join(" ") || undefined;
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-sm font-medium">
        {label}
        {required && <span aria-hidden="true" className="text-danger"> *</span>}
      </label>
      {children({ id, "aria-invalid": Boolean(error), "aria-describedby": describedBy })}
      {hint && <p id={hintId} className="text-xs text-muted">{hint}</p>}
      {error && <p id={errorId} className="text-xs font-medium text-danger"><span aria-hidden="true">✕ </span>{error}</p>}
    </div>
  );
}

export const INPUT_CLASS = cx(
  "w-full rounded-lg border border-border-strong bg-surface px-3 py-2 text-sm aria-[invalid=true]:border-danger disabled:opacity-60",
  FOCUS,
);

export function Pagination({ meta, onPage }: { meta: PageMeta; onPage: (page: number) => void }) {
  const t = useT();
  const { locale } = useLocale();
  if (meta.total_pages <= 1) return null;
  return (
    <nav aria-label={t("common.pagination")} className="mt-3 flex items-center justify-between gap-2 text-sm">
      <Button size="sm" disabled={meta.page <= 1} onClick={() => onPage(meta.page - 1)}>{t("common.previous")}</Button>
      <span aria-live="polite" className="text-muted tabular-nums">
        {t("common.pageOf", { page: formatNumber(meta.page, locale), total: formatNumber(meta.total_pages, locale), count: formatNumber(meta.total_count, locale) })}
      </span>
      <Button size="sm" disabled={meta.page >= meta.total_pages} onClick={() => onPage(meta.page + 1)}>{t("common.next")}</Button>
    </nav>
  );
}

/** A modal confirmation built on <dialog>: focus is trapped and Escape closes it natively. */
export function ConfirmDialog({ open, title, message, confirmLabel, busy, onConfirm, onCancel }: {
  open: boolean; title: string; message: string; confirmLabel: string; busy?: boolean; onConfirm: () => void; onCancel: () => void;
}) {
  const t = useT();
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog ref={ref} aria-labelledby={titleId} onCancel={(event) => { event.preventDefault(); onCancel(); }} className="m-auto w-[min(28rem,calc(100vw-2rem))] rounded-xl border border-border bg-surface p-5 text-text shadow-xl backdrop:bg-black/50">
      <h2 id={titleId} className="text-base font-semibold">{title}</h2>
      <p className="mt-2 text-sm text-muted">{message}</p>
      <div className="mt-4 flex justify-end gap-2">
        <Button onClick={onCancel} disabled={busy}>{t("common.cancel")}</Button>
        <Button variant="danger" onClick={onConfirm} disabled={busy}>{confirmLabel}</Button>
      </div>
    </dialog>
  );
}

export function PageTitle({ title, description, children }: { title: string; description?: string; children?: ReactNode }) {
  useEffect(() => {
    document.title = `${title} · SearchOps`;
  }, [title]);
  return (
    <div className="mb-6 flex flex-wrap items-start justify-between gap-x-4 gap-y-3">
      <div className="min-w-0">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        {description && <p className="mt-1 max-w-2xl text-sm text-muted">{description}</p>}
      </div>
      {children && <div className="flex flex-wrap items-center gap-2 text-sm text-muted">{children}</div>}
    </div>
  );
}
