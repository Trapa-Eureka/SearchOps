import type { Metadata, Viewport } from "next";
import { cookies, headers } from "next/headers";
import { Providers } from "@/components/providers";
import { Shell } from "@/components/shell";
import { LOCALE_COOKIE, resolveLocale } from "@/lib/i18n";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "SearchOps", template: "%s · SearchOps" },
  description: "Search rank tracking and API monitoring",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = { width: "device-width", initialScale: 1, colorScheme: "light dark" };

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const cookieStore = await cookies();
  const headerStore = await headers();
  const locale = resolveLocale(cookieStore.get(LOCALE_COOKIE)?.value, headerStore.get("accept-language"));

  return (
    <html lang={locale}>
      <body className="min-h-screen">
        <Providers locale={locale}>
          <Shell>{children}</Shell>
        </Providers>
      </body>
    </html>
  );
}
