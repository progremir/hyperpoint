<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/logo/svg/hyperpoint-horizontal-color-on-dark.svg">
    <img src="design/logo/svg/hyperpoint-horizontal-color.svg" alt="Hyperpoint" width="420">
  </picture>
</p>

<p align="center">Replace Logi Options+. Hyper key included.</p>

Hyperpoint is a small macOS menu-bar app that remaps mouse buttons, gestures and the scroll wheel, and turns Caps Lock
into a hyper key. It's one app instead of a mouse app plus a keyboard remapper, so nothing fights over your keys, and
it puts your setup back every time a device wakes or reconnects.

## Features

- **A profile per device.** Each mouse and keyboard keeps its own rules and scrolling. Start one from a preset for its
  model, from another device's profile, or empty.
- **Rules by pressing.** Click Add Rule and press a button, a key or a thumb wheel, and the rule is made for that
  control. Click a rule's button to change it the same way.
- **Hyper key.** Caps Lock becomes ⌘⌃⌥⇧ while held, per keyboard, so it can be hyper on your desk keyboard and stay
  Caps Lock on your laptop. One switch, on the Hyper Key tab or in the menu bar, turns it off on every keyboard and
  back on again.
- **Logitech buttons and gestures.** Buttons macOS never sees, like a gesture button, are taken over HID++. Click one,
  or hold it and move, to open Mission Control or App Exposé, switch Spaces or send any shortcut. A thumb wheel can be
  reversed.
- **Smooth scrolling.** Each wheel step glides as an eased pulse sized by a speed curve you edit as a graph.
- **Hold to scroll.** Hold any button and move the mouse to scroll, with momentum.
- **Hold a button, hold keys.** Any mouse button can hold a modifier or a shortcut down for as long as you hold it.
  Hold Back as ⌘ and click to ⌘-click, or hold a button as Right Option for push-to-talk dictation. Pick **Hold** under
  **When** on the Buttons tab. **Keyboard Shortcut…** records a combination, or one modifier pressed alone.
- **Mice that send keys.** Some mice send keystrokes from their extra buttons. Those keys can become modifiers or
  shortcuts for that mouse alone. A modifier is mapped at the HID layer, so it holds in password fields too.
- **Settings window and menu.** Every device Hyperpoint has seen, its rules and the scroll curve, with new devices
  to set up or ignore. The menu shows each device's state, re-applies on demand and pauses everything.

## Install

Requires macOS 27. Download `Hyperpoint-<version>.dmg` from
[hyperpoint.progremir.dev/download](https://hyperpoint.progremir.dev/download), open it and drag Hyperpoint into
Applications.

Releases are signed with Developer ID and notarized by Apple. v0.1.0 predates that: macOS refuses its first open, so
allow it under System Settings › Privacy & Security › Open Anyway.

### From source

Requires Swift 6.2 or later.

```bash
scripts/bundle.sh
```

This builds a release, signs it and installs `~/Applications/Hyperpoint.app`. It signs with a stable identity
(`SIGN_IDENTITY`, an Apple Development certificate by default) and refuses an ad-hoc signature, because macOS ties the
Accessibility and Input Monitoring grants to the signature, and an ad-hoc one would reset them on every build.

On first launch, grant Hyperpoint **Accessibility** and **Input Monitoring** in System Settings › Privacy & Security.
Until then the menu shows *Needs attention* and nothing is applied.

## Set up a device

A fresh install changes nothing, Caps Lock included. Open Settings, and the **Devices** tab lists every connected
mouse and keyboard. **Set Up** gives a device a profile, and its menu offers a preset for that model when there is one,
a copy of another device's profile, or an empty one. **Ignore** leaves the device as macOS has it. Trackpads are never
listed or changed.

A preset only fills in the first version of a profile. After that the profile is yours, and a newer preset never
changes it. To start over from a preset, click **Forget…** and set the device up again. If Hyperpoint takes a mouse
for a keyboard, as it can when the mouse's buttons send keys, switch it with the menu next to the profile's name.

### Coming from Logi Options+ or a keyboard remapper

Hyperpoint covers the buttons, gestures, thumb wheel and scrolling. It leaves out firmware updates, battery levels,
pointer speed and Flow, so keep Logi Options+ if you need those, but quit it while Hyperpoint runs: two apps setting up
the same mouse overwrite each other. The same goes for Caps Lock. If Karabiner-Elements or another remapper also maps
it, leave it to one app.

## Configuration

Everything lives in `~/.config/hyperpoint/config.json`, created with no devices on first launch. The settings window
edits this file and nothing else. An invalid file is rejected whole with the path of the error, and the last good config
keeps running. The format and the reasoning behind it are in [docs/architecture.md](docs/architecture.md).

### Manage it with an agent

[skills/hyperpoint-config](skills/hyperpoint-config/SKILL.md) is a skill for Claude Code and other agents that read
`SKILL.md` files. It knows the format and every rule the app enforces, checks an edit with its own checker before
saving it, and reads the app's log to confirm the change took. Install it once:

```bash
git clone --depth 1 https://github.com/progremir/hyperpoint.git /tmp/hyperpoint
mkdir -p ~/.claude/skills && cp -r /tmp/hyperpoint/skills/hyperpoint-config ~/.claude/skills/
```

Then ask in plain words, such as "make my mouse's back button hold ⌘". The checker works on its own too:
`python3 skills/hyperpoint-config/scripts/check_config.py` prints the first problem in your config with its path, or
the devices it sets up.

## Development

```bash
swift test
scripts/check-layers.sh
scripts/check-config-skill.py
```

`check-layers.sh` enforces the module layering described in the architecture doc. `check-config-skill.py` runs the
skill's checker against the parser's own test files, so a change to `ConfigCodec` that the checker misses fails there. To try a change on the real devices,
use the [verify-hyperpoint](.claude/skills/verify-hyperpoint/SKILL.md) skill: it replaces the running app with the
build under test and reads device state back as proof.

### Releasing

One-time setup: create a **Developer ID Application** certificate (Xcode › Settings › Accounts › Manage Certificates)
and save notarization credentials as the `hyperpoint` keychain profile with an
[app-specific password](https://account.apple.com):

```bash
xcrun notarytool store-credentials hyperpoint --apple-id <apple-id> --team-id ZZ2G9658MN
```

Publishing also uploads to Cloudflare R2, so install the site's tools and sign in to Cloudflare once, in `site/`:

```bash
npm ci && npx cf auth login
```

Then:

```bash
scripts/release.sh 0.2.0 --publish
```

This builds `dist/Hyperpoint-0.2.0.dmg`, signs the app and the DMG with Developer ID, notarizes and staples the DMG,
tags the pushed HEAD `v0.2.0` and publishes the DMG with its SHA-256 to a GitHub release and to the
`hyperpoint-releases` R2 bucket, where the site's `/download` serves it to anyone. A prerelease is uploaded but
`/download` stays on the last release. It refuses to publish without Developer ID, with uncommitted changes, with an
unpushed HEAD or without access to the bucket. Drop `--publish` to build and notarize the DMG without publishing
it. The installer window is drawn by `design/installer/build.py`; `design/installer/preview.png` shows it mounted.

To check a change to the pipeline (`build-app.sh`, `release.sh`, `dmg-settings.py` or `design/installer/`) before
merging it, build an ad-hoc DMG. This needs no certificate and skips notarization:

```bash
SIGN_IDENTITY=- ALLOW_ADHOC=1 scripts/release.sh 0.2.0-check
```

It builds, signs, checks and packs the app the same way, then verifies `dist/Hyperpoint-0.2.0-check.dmg` and writes
its SHA-256. An ad-hoc signature changes on every build, which drops the Accessibility and Input Monitoring grants,
so open this DMG to look at the installer, not to install.

The release's Developer ID signature differs from a `bundle.sh` build's Apple Development one, so switching between
the two asks for the Accessibility and Input Monitoring grants again.

## Design

<p>
  <img src="design/logo/svg/hyperpoint-app-icon.svg" alt="Hyperpoint app icon" width="128">
</p>

The mark is the **Caps pointer**: the Caps Lock glyph ⇪ tipped over until it becomes a pointer. Caps Lock is the key
Hyperpoint turns into hyper, and the pointer is what it drives. The bar under the arrow is the key's lit LED and
carries the one accent colour.

| | Colour | Use |
|---|---|---|
| <img src="design/logo/svg/hyperpoint-swatch-ink.svg" width="16" alt=""> | Ink `#18181D` | Glyph, wordmark, app-icon tile |
| <img src="design/logo/svg/hyperpoint-swatch-accent.svg" width="16" alt=""> | Caps Green `#52E07A` | The bar only, on dark backgrounds |
| <img src="design/logo/svg/hyperpoint-swatch-accent-deep.svg" width="16" alt=""> | Deep Green `#138A48` | One-colour logo on white |

The full kit is in [design/logo/](design/logo/): SVG and PNG masters, lockups, `AppIcon.icns`, the menu-bar template
icon, web icons and the [usage guidelines](design/logo/README.md). `scripts/bundle.sh` takes the app and menu-bar
icons straight from `design/logo/macos/`. Everything in the kit is generated; change the geometry in
`design/logo/build.py` and run `python3 design/logo/build.py`.
