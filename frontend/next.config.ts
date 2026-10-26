import type { NextConfig } from "next";

// The browser only ever talks to this app. Requests to /api/* are forwarded to the Rails API by
// the Next.js server, so no CORS setup is needed, the Rails address is not exposed to the
// browser, and the dashboard holds no credentials (the SerpApi key lives only in the Rails
// process). API_BASE_URL is server-side only: it is deliberately not a NEXT_PUBLIC_ variable.
const apiBaseUrl = (process.env.API_BASE_URL ?? "http://127.0.0.1:3000").replace(/\/+$/, "");

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  // No next/image is used, so the image optimization endpoint is switched off entirely.
  images: { unoptimized: true },
  async rewrites() {
    return [{ source: "/api/:path*", destination: `${apiBaseUrl}/api/:path*` }];
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Referrer-Policy", value: "same-origin" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
        ],
      },
    ];
  },
};

export default nextConfig;
