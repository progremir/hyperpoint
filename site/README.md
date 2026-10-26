# Hyperpoint website

A static landing page: plain HTML, CSS and JavaScript with no build step. It was designed with the
[`landing-page-design`](https://github.com/elayadesign/ai-design-skills/tree/main/skills/landing-page-design) and
[`design-to-motion`](https://github.com/elayadesign/ai-design-skills/tree/main/skills/design-to-motion) skills.

```bash
python3 -m http.server 4319 --directory site
```

Serve `site/` from the root of a domain. `404.html` and `privacy.html` use root paths (`/styles.css`), so they work
at any depth. Once the site has a domain, make `og:image` in `index.html` an absolute URL. The download buttons link
to the latest GitHub release, which only people with access to the repository can open while it is private.

| File | What it is |
|---|---|
| `index.html` | The page. The icon sprite (Phosphor, MIT), the config excerpt and the FAQ schema are written inline |
| `styles.css` | Tokens and every section's styles |
| `main.js` | Island nav, scroll reveals, card intros and stories, the tagline reveal |
| `404.html`, `privacy.html` | The branded 404 and the privacy page |
| `og.png` | Social preview, drawn by `og.py` from the logo kit and Geist |
| `favicon.*`, `icon-*.png`, `site.webmanifest`, `assets/` | Copied from `design/logo/` |

## The brief

**One offer, one audience, one action.** Hyperpoint for Mac users who set up a mouse and Caps Lock with BetterMouse
and Karabiner, often with an MX Master 3 that forgets its buttons on reconnect. The one action is *Download for Mac*.

**Layout: A, classic hero plus sections.** The product reads at a glance from its menu bar menu, so the hero shows
that menu with real device rows and the reconnect note.

**Hero.** *Your mouse setup, still there after every reconnect.* The subheadline says what it is and does, the CTA
downloads, and the proof line says it is notarized, its version and what it runs on.

**Order.** Hero, problem to solution (before and after), tagline reveal, four benefit cards with stories, three
smaller features, how it works in three steps, proof (the owner's real config and six facts), FAQ (12 questions with
FAQ schema), final CTA with risk reversal, footer.

**Benefits.** Settings that survive sleep. A hyper key on Caps Lock. A wheel that glides. Change a button by pressing
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
| Settings card | The mouse disconnects, its checks clear, it reconnects, each setting is written back, the time updates |
| Hyper key card | Caps Lock goes down, the four modifiers light, T sends ⌃⌥⇧⌘T, everything lets go |
| Wheel card | A dot rides the real speed curve from a slow turn to a flick and back while the readout counts |
| Rules card | Add Rule listens, a press lands as a new rule on top, the others step down |
| Tagline | Each word lights up in reading order as the section scrolls |
| Text sections | Fade up from blur as they enter the viewport |

The card and curve data come from the app: the menu strings from `StatusMenu.swift` and `MenuPresentation.swift`, the
rules from the MX Master 3 preset, and the curve and measured wheel bands from `SpeedCurve.swift` and
`CurveGraph.swift`. Update the page when those change. The sizes (1.2 MB download, 3.3 MB installed) are measured from
the v0.1.1 DMG and the app inside it, so check them on each release.
