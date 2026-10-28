# Hyperpoint website

A landing page in plain HTML, CSS and JavaScript with no build step, plus a small Worker that serves the downloads.
It was designed with the
[`landing-page-design`](https://github.com/elayadesign/ai-design-skills/tree/main/skills/landing-page-design) and
[`design-to-motion`](https://github.com/elayadesign/ai-design-skills/tree/main/skills/design-to-motion) skills.

Live at https://hyperpoint.progremir.dev, served by the `hyperpoint` Worker on Cloudflare.

```bash
python3 -m http.server 4319 --directory site/public
```

That serves the page alone. To try `/download` too, run the Worker with a local bucket, filled with
`npx wrangler r2 object put hyperpoint-releases/<key> --local --persist-to .wrangler/state --file <file>` in `site/`:

```bash
site/node_modules/.bin/wrangler dev -c site/wrangler.jsonc --port 8787 --persist-to site/.wrangler/state
```

**Deploying.** Cloudflare's Workers Builds builds `site/` on every push that touches it. A push to `main` runs
`npx wrangler deploy` and updates the live site. A push to any other branch runs `npx wrangler preview`, which
publishes that branch at `https://<branch>-hyperpoint.progremir.workers.dev` (public, but sent with `X-Robots-Tag:
noindex`). Both read `wrangler.jsonc`, so a change to the Worker's entry, assets or bindings goes there as well as in
`cloudflare.config.ts`, and a binding goes in its `previews` block too, since previews inherit none. Both run in `site/` on Node 24 (`.node-version`) with Cloudflare's own build token, so the repository
holds no Cloudflare secret. The connection lives on the Worker in the Cloudflare dashboard, under Settings ›
Builds, and Cloudflare posts each branch's preview link on its pull request.
`cloudflare.config.ts` holds the Worker's name, account, domain, preview URLs, 404 handling, entry and bindings for
`npx cf deploy` and `npx cf previews deploy` from a Mac, and `wrangler.config.ts` names `public/` as the assets, so
only that folder and the Worker are uploaded.

`404.html` and `privacy.html` use root paths (`/styles.css`), so they work at any depth.

**Downloads.** The download buttons link to `/download`, which needs no GitHub account or repository access. The
Worker runs only for `/download` paths and reads the private `hyperpoint-releases` R2 bucket, which
`scripts/release.sh --publish` fills: `/download` redirects to the file its `latest` object names, and
`/download/Hyperpoint-<version>.dmg` and its `.sha256` serve that release. Any other path, in the bucket or not, gets
the 404 page. To point `/download` at another release, run in `site/`:

```bash
npx cf r2 objects put latest --bucket-name hyperpoint-releases --body Hyperpoint-0.1.1.dmg --content-type "text/plain; charset=utf-8"
```

| File | What it is |
|---|---|
| `public/index.html` | The page. The icon sprite (Phosphor, MIT), the config excerpt and the FAQ schema are written inline |
| `public/styles.css` | Tokens and every section's styles |
| `public/main.js` | Island nav, scroll reveals, card intros and stories, the tagline reveal |
| `public/404.html`, `public/privacy.html` | The branded 404 and the privacy page |
| `public/og.png` | Social preview, drawn by `og.py` from the logo kit and Geist |
| `public/favicon.*`, `icon-*.png`, `site.webmanifest`, `assets/` | Copied from `design/logo/` |
| `src/index.ts` | The Worker that serves `/download` from R2 |
| `cloudflare.config.ts`, `wrangler.config.ts`, `wrangler.jsonc`, `package.json` | The Cloudflare project; `cf` and Wrangler are pinned in `package-lock.json` |

## The brief

**One offer, one audience, one action.** Hyperpoint for Mac users who run Logi Options+ for the mouse and a separate
remapper for Caps Lock, and want one app that nothing conflicts with. The one action is *Download for Mac*.

**Layout: A, classic hero plus sections.** The product reads at a glance from its menu bar menu, so the hero shows
that menu with real device rows.

**Hero.** *Replace Logi Options+. Hyper key included.* The subheadline says what it does and why one app beats two:
nothing to clash with, no account, and a profile for every mouse and keyboard. The CTA downloads, and the proof line
says it is notarized, its size and what it runs on.

**Not a pitch.** Hyperpoint puts a device's settings back when it wakes or reconnects, but that works around other
apps' and devices' behavior, so the page never sells it. Lead with what the app does.

**Order.** Hero, problem to solution (before and after), tagline reveal, four benefit cards with stories, three
smaller features, how it works in three steps, proof (the owner's real config and six facts), FAQ (13 questions with
FAQ schema), final CTA with risk reversal, footer.

**Benefits.** A profile for every device. A hyper key on Caps Lock. A wheel that glides. Change a button by pressing
it.

**Steps.** Install and allow two permissions. Set up each device. Press a button to add a rule.

**Proof without testimonials.** There are no users to quote yet, and invented quotes would be fake. The proof is the
config file of the Mac Hyperpoint was built on, plus facts taken from the code: notarized releases, no network code,
an invalid file rejected whole, key mappings cleared on quit.

**Risk reversal.** A fresh install changes nothing until a device is set up, and quitting puts the keys back.

**SEO.** Index it: the offer is evergreen. Title, description, Open Graph, a `SoftwareApplication` schema and the FAQ
as `FAQPage`.

## The visual system

- Dark only, on purpose. Caps Green is made for dark grounds, and on this page green always means *on* or *applied*,
  like the key's lit LED in the logo.
- Geist for everything, Geist Mono only for chords, numbers and the config. Sizes stay on Tailwind's type scale,
  spacing on the skill's 2 to 96 px steps, radii on Tailwind's, with nested radii derived from their parent.
- No background gradients. The one gradient is the hero heading's white to grey text.
- Motion uses the skills' curves: `cubic-bezier(0.32, 0.72, 0, 1)` for reveals and the nav, the design-to-motion
  set for card intros and stories. `prefers-reduced-motion` shows every section at rest, with no stories.

## What moves

| Section | Motion |
|---|---|
| Hero menu | The desk, menu bar and menu stay; their rows load in order |
| Cards | Rise in when 30% visible, then each visual tells its story on a loop, paused off screen |
| Profiles card | The panel steps from MX Master 3 to 2.4G Mouse to Magic Keyboard, and the rules and where they came from change with it |
| Hyper key card | Caps Lock goes down, the four modifiers light, T sends ⌃⌥⇧⌘T, everything lets go |
| Wheel card | A dot rides the real speed curve from a slow turn to a flick and back while the readout counts |
| Rules card | Add Rule listens, a press lands as a new rule on top, the others step down |
| Tagline | Each word lights up in reading order as the section scrolls |
| Text sections | Fade up from blur as they enter the viewport |

The card and curve data come from the app: the menu strings from `StatusMenu.swift` and `MenuPresentation.swift`, the
rules and profiles from the presets in `Presets.swift`, and the curve and measured wheel bands from `SpeedCurve.swift` and
`CurveGraph.swift`. Update the page when those change. The sizes (1.2 MB download, 3.3 MB installed) are measured from
the v0.1.1 DMG and the app inside it, so check them on each release.
