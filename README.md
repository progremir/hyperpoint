<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/logo/svg/hyperpoint-horizontal-color-on-dark.svg">
    <img src="design/logo/svg/hyperpoint-horizontal-color.svg" alt="Hyperpoint" width="420">
  </picture>
</p>

<p align="center">A macOS menu-bar app for your mouse and keys, re-applied every time a device reconnects.</p>

Hyperpoint replaces BetterMouse and Karabiner-Elements. Each keyboard and mouse you set up gets a profile in one config
file, started from a preset for that device or from another device's profile. Devices forget their settings often (HID++
diverts are lost on sleep and reconnect, a key mapping dies with its HID service), so Hyperpoint computes the state each
device should be in from that file and writes all of it back whenever a device appears.

## Features

- **Hyper key.** Caps Lock becomes ⌘⌃⌥⇧ while held, per keyboard.
- **MX Master buttons and gestures.** The gesture and top buttons are diverted over HID++ and mapped to Mission
  Control, App Exposé, Space switching or any shortcut. The thumb wheel can be reversed.
- **Smooth scrolling.** Each wheel step glides as an eased pulse sized by a speed curve you edit as a graph.
- **Hold to scroll.** Hold a button and move the mouse to scroll, with momentum. The MX Master 3 preset gives it to the
  right button, and any button can be given the rule.
- **Other mice.** Keys sent by a mouse's keyboard interface (like the 2.4G mouse's Escape and Return) can become
  modifiers or shortcuts.
- **Settings window and menu.** Every device Hyperpoint has seen, its rules and the scroll curve, with new devices
  to set up or ignore. The menu shows each device's state, re-applies on demand and pauses everything.

## Install

Requires macOS 27. Download `Hyperpoint-<version>.dmg` from
[Releases](https://github.com/progremir/hyperpoint/releases), open it and drag Hyperpoint into Applications.

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

## Set up your devices

A fresh install has no devices in its config and changes nothing, Caps Lock included. Open Settings, and the
**Devices** tab lists every connected keyboard and mouse as new. Click **Set Up** to give a device a profile, or
**Ignore** to leave it as macOS has it and stop listing it.

The button applies the best choice for that device, and its menu holds the others:

| Choice | Offered for | What it sets |
|---|---|---|
| MX Master 3 preset | The MX Master 3 (`0x046D:0xB023`) | The gesture button opens Mission Control, App Exposé and the Spaces left and right. The top button sends ⇧⌘4. The thumb wheel is reversed, the wheel scrolls smoothly, and holding the right button scrolls. |
| 2.4G mouse preset | The 2.4G mouse (`0x1EA7:0x0002`) | Escape becomes Right Option while held, and Return sends ⌥⇧S. |
| Hyper key | Any keyboard | The hyper key. |
| Nothing yet | Any mouse | No rules. Add them on the **Buttons** tab. |
| Same as *a profile* | A device of the same kind as that profile | A copy of that profile's rules, gestures, scrolling and hyper key. |

A preset only starts the profile. After Set Up the config file holds every setting, and a later change to a preset does
not touch a saved profile. To start a device again from a preset, click **Forget…** and set it up again.

Hyperpoint sees keyboards, Logitech HID++ devices, and mice that also send keys. A plain mouse with only a pointer
interface does not show up yet.

## Configuration

Everything lives in `~/.config/hyperpoint/config.json`, created with no devices on first launch. The settings window
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

### Releasing

One-time setup: create a **Developer ID Application** certificate (Xcode › Settings › Accounts › Manage Certificates)
and save notarization credentials as the `hyperpoint` keychain profile with an
[app-specific password](https://account.apple.com):

```bash
xcrun notarytool store-credentials hyperpoint --apple-id <apple-id> --team-id ZZ2G9658MN
```

Then:

```bash
scripts/release.sh 0.2.0 --publish
```

This builds `dist/Hyperpoint-0.2.0.dmg`, signs the app and the DMG with Developer ID, notarizes and staples the DMG,
tags the pushed HEAD `v0.2.0` and publishes the DMG with its SHA-256 to a GitHub release. It refuses to publish without
Developer ID, with uncommitted changes or with an unpushed HEAD. Drop `--publish` to only build the DMG. Pull requests
that touch the pipeline run `.github/workflows/release.yml`, which builds an ad-hoc DMG on CI as an artifact. The
installer window is drawn by `design/installer/build.py`; `design/installer/preview.png` shows it mounted.

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
