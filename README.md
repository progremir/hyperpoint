<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/logo/svg/hyperpoint-horizontal-color-on-dark.svg">
    <img src="design/logo/svg/hyperpoint-horizontal-color.svg" alt="Hyperpoint" width="420">
  </picture>
</p>

<p align="center">A macOS menu-bar app for your mouse and keys, re-applied every time a device reconnects.</p>

Hyperpoint replaces BetterMouse and Karabiner-Elements for one setup: an MX Master 3, a 2.4G mouse, and the built-in
and Magic keyboards. Devices forget their settings often (HID++ diverts are lost on sleep and reconnect, a key mapping
dies with its HID service), so Hyperpoint computes the state each device should be in from one config file and writes
all of it back whenever a device appears.

## Features

- **Hyper key.** Caps Lock becomes ⌘⌃⌥⇧ while held, per keyboard.
- **MX Master buttons and gestures.** The gesture and top buttons are diverted over HID++ and mapped to Mission
  Control, App Exposé, Space switching or any shortcut. The thumb wheel can be reversed.
- **Smooth scrolling.** Each wheel step glides as an eased pulse sized by a speed curve you edit as a graph.
- **Other mice.** Keys sent by a mouse's keyboard interface (like the 2.4G mouse's Escape and Return) can become
  modifiers or shortcuts.
- **Settings window and menu.** Every device Hyperpoint has seen, its rules, and the scroll curve. The menu shows each
  device's state, re-applies on demand and pauses everything.

## Install

Requires macOS 27 and Swift 6.2 or later.

```bash
scripts/bundle.sh
```

This builds a release, signs it and installs `~/Applications/Hyperpoint.app`. It signs with a stable identity
(`SIGN_IDENTITY`, an Apple Development certificate by default) and refuses an ad-hoc signature, because macOS ties the
Accessibility and Input Monitoring grants to the signature, and an ad-hoc one would reset them on every build.

On first launch, grant Hyperpoint **Accessibility** and **Input Monitoring** in System Settings › Privacy & Security.
Until then the menu shows *Needs attention* and nothing is applied.

## Configuration

Everything lives in `~/.config/hyperpoint/config.json`, created from the defaults on first launch. The settings window
edits this file and nothing else. An invalid file is rejected whole with the path of the error, and the last good config
keeps running. The format and the reasoning behind it are in [docs/architecture.md](docs/architecture.md).

## Development

```bash
swift test
scripts/check-layers.sh
```

`check-layers.sh` enforces the module layering described in the architecture doc. To try a change on the real devices,
use the [verify-hyperpoint](.claude/skills/verify-hyperpoint/SKILL.md) skill: it replaces the running app with the
build under test and reads device state back as proof.

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
