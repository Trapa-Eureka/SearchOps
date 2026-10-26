"use client";

import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from "react";

export type ToastTone = "success" | "error" | "info";
type Toast = { id: number; message: string; tone: ToastTone };
type ToastContextValue = { push: (message: string, tone?: ToastTone) => void };

const ToastContext = createContext<ToastContextValue | null>(null);
const TONE_CLASS: Record<ToastTone, string> = {
  success: "border-ok bg-ok-bg text-ok",
  error: "border-danger bg-danger-bg text-danger",
  info: "border-info bg-info-bg text-info",
};
const TONE_ICON: Record<ToastTone, string> = { success: "✓", error: "✕", info: "ℹ" };

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const nextId = useRef(1);

  const push = useCallback((message: string, tone: ToastTone = "info") => {
    const id = nextId.current++;
    setToasts((current) => [...current, { id, message, tone }]);
    window.setTimeout(() => setToasts((current) => current.filter((toast) => toast.id !== id)), 7000);
  }, []);

  const value = useMemo(() => ({ push }), [push]);
  return (
    <ToastContext.Provider value={value}>
      {children}
      {/* A polite live region: screen readers announce each message without stealing focus. */}
      <div aria-live="polite" role="status" className="pointer-events-none fixed inset-x-0 bottom-4 z-50 flex flex-col items-center gap-2 px-4">
        {toasts.map((toast) => (
          <p key={toast.id} className={`pointer-events-auto max-w-xl rounded-md border px-4 py-2 text-sm shadow-md ${TONE_CLASS[toast.tone]}`}>
            <span aria-hidden="true" className="mr-2 font-bold">{TONE_ICON[toast.tone]}</span>
            {toast.message}
          </p>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const value = useContext(ToastContext);
  if (!value) throw new Error("useToast must be used inside <ToastProvider>");
  return value;
}
