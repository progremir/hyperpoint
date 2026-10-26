import { defineConfig } from "cf/config";

// The site is static: wrangler.config.ts names public/ as the assets, and there is no Worker code.
export default defineConfig({
  accountId: "dd1171d285218486ca1fb1fcec2a759c",
  worker: {
    name: "hyperpoint-site",
    compatibilityDate: "2026-10-19",
    domains: ["hyperpoint.progremir.dev"],
    assets: { htmlHandling: "auto-trailing-slash", notFoundHandling: "404-page" },
    observability: { enabled: true },
  },
});
