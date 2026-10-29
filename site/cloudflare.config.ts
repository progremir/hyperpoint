import { bindings, defineConfig } from "cf/config";

// wrangler.config.ts names public/ as the assets. src/index.ts runs only for /download, which serves release DMGs
// from R2, and for /appcast.xml, the Sparkle feed beside them.
export default defineConfig({
  accountId: "dd1171d285218486ca1fb1fcec2a759c",
  worker: {
    name: "hyperpoint",
    compatibilityDate: "2026-10-19",
    entrypoint: "./src/index.ts",
    domains: ["hyperpoint.progremir.dev"],
    // Production is served only on the domain. Previews get noindexed workers.dev URLs.
    workersDev: false,
    previewUrls: true,
    assets: {
      htmlHandling: "auto-trailing-slash",
      notFoundHandling: "404-page",
      runWorkerFirst: ["/download", "/download/*", "/appcast.xml"],
    },
    env: {
      ASSETS: bindings.assets(),
      RELEASES: bindings.r2({ name: "hyperpoint-releases" }),
    },
    observability: { enabled: true },
  },
});
