// Serves the release DMGs that scripts/release.sh uploads to the hyperpoint-releases R2 bucket, so downloading needs
// no access to the private repository. /download redirects to the release the bucket's `latest` object names, so the
// saved file carries its version. The Worker runs only for /download paths; everything else is a static asset.
interface Env {
  ASSETS: Fetcher;
  RELEASES: R2Bucket;
}

// Only release files are served; `latest` and anything else in the bucket stay private.
const RELEASE_FILE = /^Hyperpoint-[0-9A-Za-z.-]+\.dmg(\.sha256)?$/;

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    const key = new URL(request.url).pathname.replace(/^\/download\/?/, "");
    if (key === "") {
      const latest = await env.RELEASES.get("latest");
      if (latest === null) return env.ASSETS.fetch(request);
      const location = `/download/${(await latest.text()).trim()}`;
      return new Response(null, { status: 302, headers: { Location: location, "Cache-Control": "no-store" } });
    }
    const object = RELEASE_FILE.test(key) ? await env.RELEASES.get(key) : null;
    // The assets binding answers an unknown path with the site's 404 page.
    if (object === null) return env.ASSETS.fetch(request);
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("ETag", object.httpEtag);
    // A version's files never change: release.sh stops at an existing tag before it uploads anything.
    headers.set("Cache-Control", "public, max-age=31536000, immutable");
    return new Response(object.body, { headers });
  },
} satisfies ExportedHandler<Env>;
