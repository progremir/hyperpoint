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
Worker runs only for `/download` paths and `/appcast.xml`, and reads the private `hyperpoint-releases` R2 bucket, which
`scripts/release.sh --publish` fills: `/download` redirects to the file its `latest` object names, and
`/download/Hyperpoint-<version>.dmg` and its `.sha256` serve that release. `/appcast.xml` serves the bucket's
`appcast.xml`, the signed Sparkle feed that installed copies read to update themselves, which `release.sh` rebuilds on
each release; it is sent with `Cache-Control: no-cache`. Any other path, in the bucket or not, gets the 404 page.
To point `/download` at another release, run in `site/`:

```bash
npx cf r2 objects put latest --bucket-name hyperpoint-releases --body Hyperpoint-0.1.1.dmg --content-type "text/plain; charset=utf-8"
```

| File | What it is |
|---|---|
| `public/index.html` | The page. Its two icons (the Apple logo from Simple Icons, CC0, and Phosphor's shield, MIT) and the `SoftwareApplication` schema are written inline |
| `public/styles.css` | Tokens and every section's styles |
| `public/main.js` | Scroll reveals, and the film: the stage of objects behind the page, their arrangement per section, the wheel feeds and the shortcut count |
| `public/assets/sprite-*.webp` | The stage's objects, each alone on a transparent ground (see below) |
| `public/assets/keys-*.webp` | Each section's still picture, for reduced motion and no script, at 1x and 2x |
| `public/404.html`, `public/privacy.html` | The branded 404 and the privacy page |
| `public/og.png` | Social preview, drawn by `og.py` from the logo kit and Geist |
| `public/favicon.*`, `icon-*.png`, `site.webmanifest`, `assets/*.svg` | Copied from `design/logo/` |
| `src/index.ts` | The Worker that serves `/download` and `/appcast.xml` from R2 |
| `cloudflare.config.ts`, `wrangler.config.ts`, `wrangler.jsonc`, `package.json` | The Cloudflare project; `cf` and Wrangler are pinned in `package-lock.json` |

## The brief

**One offer, one audience, one action.** Hyperpoint for Mac users who run Logi Options+ for the mouse and a separate
remapper for Caps Lock, and want one app that nothing conflicts with. The one action is *Download for Mac*.

**Layout: a short page, cut like the film.** The page is cut like the keycaps launch film,
`design/demo-video/keycaps.html`, so someone who watched it lands on the same frames. The mouse comes first and the
hyper key second, as the headline says: the hero is the film's mouse with its Caps Lock key beside it, each named by a
pill, and the page closes on the film's end card. It keeps only the film's beats; the longer explanations (how it
works, the config, the FAQ) live in the README on GitHub.

**Hero.** *Replace Logi Options+. Hyper key included.* The subheadline is two short lines, one thought each: what it is (a small
menu bar app for your mouse and keyboard), then why one app beats two (nothing to clash with, no account). The details
are left to the beats below. The CTA downloads, and the proof line
says it is notarized, its size and what it runs on.

**Not a pitch.** Hyperpoint puts a device's settings back when it wakes or reconnects, but that works around other
apps' and devices' behavior, so the page never sells it. Lead with what the app does.

**Order.** Hero, three beats from the film, final CTA, footer. The nav is the logo and the
download pill; there is nothing to jump to.

**Benefits.** In the film's words, mouse first: every button on your mouse, and a wheel that glides. Then a spare key
on your keyboard: Caps Lock, held, is ⌘⌥⇧⌃.

**No testimonials.** There are no users to quote yet, and invented quotes would be fake.

**Final CTA.** The film's end card: *One app for your mouse*, the last word swapping to *keyboard*, the cream Download
pill and the address, centered between the mouse on the left and Caps Lock on the right. The film's own fine print still says 1.2 MB and predates Sparkle; the page uses the measured
sizes below.

**SEO.** Index it: the offer is evergreen. Title, description, Open Graph and a `SoftwareApplication` schema. No
`FAQPage`: structured data has to match what the page shows, and the FAQ is not on it.

## The visual system

The keycaps film, `design/demo-video/keycaps.html`, sets the look. When it changes, change the page with it.

- Dark only, on purpose: the film's near-black `#050506`, with its grain over everything at the same strength, and
  its warm white `#f4f2ee` and dim `#9a9894` for type.
- Geist at weight 500 for headings, with one word in Instrument Serif italic, as the film's end card sets *mouse*.
  Geist Mono for small print and numbers; the system font for key glyphs, as macOS draws them.
- One alignment: everything is centered, as the film's frames are.
- The film's heads: centered, two lines, the second dim.
- Translucent pills with a 1.5 px inset edge label things, as in the film. The download button is its cream pill,
  with the Apple logo (Simple Icons, CC0) where the film draws a download arrow.
- Green is the keycaps' Caps Green: what is on, and what is Hyperpoint (the callouts' names, its feed).
- The 3D is pictures, not three.js: the film's keys and mouse rendered from its own scene (below), so the page loads
  no WebGL and no 4.9 MB model.
- Motion uses the skills' curves: `cubic-bezier(0.32, 0.72, 0, 1)` for reveals and the nav, the film's
  `cubic-bezier(0.16, 1, 0.3, 1)` and its in-out curve for the rest. `prefers-reduced-motion` shows every section at
  rest, with no stories.

## What moves

The page plays like the film. Its objects (the mouse, Caps Lock, the keys Caps Lock turns into shortcuts and six loose
keys) live on one stage fixed behind the whole page, and only the text scrolls past. Each `[data-scene]` section (the
hero, the mouse's buttons, its wheel, the hyper key, the end card) has its own arrangement of them in `main.js`, one
for wide screens and one for phones. Scrolling eases them from one arrangement to the next, holding still while a
section's middle is near the middle of the screen; the mouse turns from its front to its side for the wheel. Each
object also drifts on its own all the time, and the text has a soft dark halo for when they pass behind it.

| Section | Motion |
|---|---|
| Hero | Loose keys drift behind the headline; the mouse and Caps Lock below |
| Buttons | The mouse comes to the middle; its callouts' pills and leaders appear, and each control glows on a loop |
| Wheel | The mouse turns to its side and its wheel spins, beside two feeds: a plain one steps a row per notch, Hyperpoint's eases each one, from the film's notch timing |
| Hyper key | Caps Lock comes to the middle between its clusters of keys; the line under it names a new shortcut key every 0.4 s |
| End card | The mouse and Caps Lock frame the copy; *mouse* and *keyboard* swap |
| Text | Fades up from blur as it enters the viewport |

With reduced motion, or without the script, there is no stage: each section shows its own still picture
(`.static`), with its labels laid out around it.

**The sprites.** `assets/sprite-*.webp` are the film's objects rendered alone from its own three.js scene, at 2x on a
transparent ground and trimmed to their pixels: the mouse from the front (the hero's pose) and from the side (14 s),
its wheel in six frames through one notch (`sprite-wheel`, a strip drawn over the side view), Caps Lock, the clusters
from 4.8 s without Caps Lock, and the end card's six loose keys, K and J pre-blurred on the film's near and far layers.
The callouts' leaders run from where the film projects the right button, thumb buttons and wheel onto the front view.

**The stills.** `assets/keys-*.webp` are frames of the film's three.js scene with its text, grain and ground hidden:
the opening at 4.8 s (`caps`), the mouse at 11.6 s and 14 s with its glows off, and the end
card at 20 s as two layers, sharp and the far blurred keys. The hero is the end card's keys and mouse posed anew at
20 s: the mouse at (-2, 0.05, 0) turned (24°, 120°, 2°) at 2.7×, Caps Lock at (3.7, 0.6, 0) at 1.5×, the rest around
them. `end-wide`, the end card on wide screens, poses them the same way around an empty middle for the copy: the mouse
at (-5.5, -0.6, 0.4) at 1.6×, Caps Lock at (5.4, 0.9, 0) at 1.45×, full frame. Phones keep the film's own end-card
layers above the copy. Render them the way `render.cjs` renders the film, from a
copy of `keycaps.html` drawn at 2x on a transparent ground, trim each to its pixels and encode it with alpha
(`cwebp -q 80 -alpha_q 80 -sharp_yuv`), at 2x and at half that. The mouse callouts are placed in the film's own
pixels: the leaders run from where the film projects the right button, thumb buttons and wheel at 11.6 s. The size (2.3 MB download) is measured from a DMG built by
`release.sh` on 29 October 2026, the first with Sparkle, so check it on each release.
