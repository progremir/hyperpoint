---
name: hyperpoint-config
description: Read, explain and change the Hyperpoint config file (~/.config/hyperpoint/config.json), which sets up mouse buttons, Logitech gestures, smooth scrolling, hold to scroll and the Caps Lock hyper key on macOS. Use whenever the user wants to remap a mouse button or a key a mouse sends, add or change a Hyperpoint rule or shortcut, tune scrolling, set up or ignore a mouse or keyboard, turn the hyper key on or off, or asks what their Hyperpoint setup does, even if they never name the file.
---

# Hyperpoint config

Hyperpoint is a macOS menu bar app. Everything it does comes from one JSON file:

```
~/.config/hyperpoint/config.json
```

The app watches that file and applies it the moment it is saved, to every connected device. Its settings window
edits the same file and nothing else. A file with any mistake is rejected whole: the app keeps running the last good
settings and its menu shows "Config file has an error" with the path of the mistake, such as
`devices[1].rules[0].when`. So a bad edit never breaks the user's mouse, but it also changes nothing until it is fixed.

## Workflow

1. **Read the current file** and say in plain words what it sets up before changing anything.

   ```bash
   cat ~/.config/hyperpoint/config.json
   ```

2. **Back it up.**

   ```bash
   cp ~/.config/hyperpoint/config.json ~/.config/hyperpoint/config.json.bak
   ```

3. **Make the smallest edit that does what the user asked.** Keep every other device, rule and setting as it is.
   Write the new version to a temporary file first, for example by loading the JSON, changing it and dumping it with
   two-space indentation.

4. **Check it with the bundled checker** before it replaces the real file. It applies the app's own rules and
   prints the first problem with the same path the app would show.

   ```bash
   python3 <this skill's folder>/scripts/check_config.py /tmp/hyperpoint-config.json
   ```

   Fix what it reports and check again. When it prints `ok`, move the file into place:

   ```bash
   mv /tmp/hyperpoint-config.json ~/.config/hyperpoint/config.json
   ```

5. **Confirm the app took it.** Use `/usr/bin/log`, because zsh has a `log` builtin that prints nothing here.

   ```bash
   /usr/bin/log show --last 2m --style compact --predicate 'subsystem == "dev.emir.hyperpoint"' \
     | grep -E 'state=|reasons=configChanged'
   ```

   A `state=` line with `notices=[Config file has an error]` means the app rejected the file: restore the backup or
   fix it. Otherwise the app applied it. Devices whose keys it maps (keyboards with the hyper key, mice with key
   rules) log `apply ... reasons=configChanged ... applied`, and a Logitech mouse whose diverted controls changed logs
   `hidpp ... reasons=configChanged ... applied`. Changing only what a button does logs nothing, and the menu logs a
   `state=` line only when what it shows changes, so a quiet log after a clean check is normal. If
   `pgrep -x Hyperpoint` prints nothing, the app is not running and reads the file at its next launch.

6. **Tell the user what changed** in terms of buttons and keys ("the gesture button now opens Mission Control"),
   and what to press to try it.

## Finding a device

Each profile names its device by vendor and product id, written as 4-digit hex strings, or as
`{ "builtIn": true }` for the Mac's own keyboard.

Hyperpoint logs every device it sees, with its ids, and `profile=none` for one that has no profile yet:

```bash
/usr/bin/log show --last 7d --style compact \
  --predicate 'subsystem == "dev.emir.hyperpoint" AND category == "devices"' | grep -E ' (present|connect) '
```

Without the log, `hidutil list` shows every HID device with its `VendorID` and `ProductID` (`0x46d` becomes
`"0x046D"`). Trackpads, including the built-in one, cannot be configured.

For a Logitech mouse, the `discovered` lines in the same log list its HID++ controls, for example
`controls=[0x50,0x51,0x52+divert+rawXY,...,0xC3+divert+rawXY] thumbWheel=true`. Only a control marked `+divert` can
have a rule, and only one marked `+rawXY` can take hold-and-move rules. Known ids: `0x50` left, `0x51` right, `0x52`
middle, `0x53` back, `0x56` forward, `0xC3` gesture button, `0xC4` top button (MX Master 3). When the user cannot
say which control a button is, have them open Settings › Buttons, click Add Rule and press it: the app writes a rule
for exactly that control, which you can then edit.

## The file

```json
{
  "version": 1,
  "hyper": { "enabled": true, "key": "capsLock", "onTap": "nothing" },
  "devices": [
    {
      "match": { "vendor": "0x046D", "product": "0xB023" },
      "name": "MX Master 3",
      "rules": [
        { "control": { "hidpp": "0xC3" }, "when": "click", "do": "missionControl" },
        { "control": { "hidpp": "0xC3" }, "when": "holdMoveLeft", "do": "spaceLeft" },
        { "control": { "hidpp": "0xC4" }, "when": "click", "do": { "shortcut": "shift+cmd+4" } },
        { "control": "thumbWheel", "when": "scroll", "do": "reverse" },
        { "control": { "button": 1 }, "when": "holdMove", "do": "scroll" }
      ],
      "gestures": { "fire": "pastDistance", "distance": 120 },
      "scrolling": {
        "smooth": { "duration": 4, "brake": 2, "easeIn": 60, "curve": [
          { "stepsPerSecond": 1, "pointsPerSecond": 40 },
          { "stepsPerSecond": 120, "pointsPerSecond": 9000 }
        ] },
        "holdToScroll": { "speed": 1, "direction": "grab", "momentum": true }
      }
    },
    { "match": { "vendor": "0x1EA7", "product": "0x0002" }, "name": "2.4G Mouse", "kind": "mouse", "rules": [
      { "control": { "key": "escape" }, "when": "hold", "do": { "modifier": "rightOption" } },
      { "control": { "key": "return" }, "when": "click", "do": { "shortcut": "opt+shift+s" } }
    ] },
    { "match": { "builtIn": true }, "name": "Built-in Keyboard", "hyper": true }
  ],
  "ignored": []
}
```

**Top level.** `version` is always `1`. `devices` holds one profile per device. `ignored` lists matches for devices
the user chose to leave alone; a device cannot be in both.

**`hyper`** applies to every keyboard whose profile has `"hyper": true`. `key` is the key that becomes the hyper key
(⌃⌥⇧⌘ while held), almost always `"capsLock"`. `onTap` can only be `"nothing"` for now. `enabled: false` turns the
hyper key off on every keyboard while each profile keeps its own `hyper` for later.

**A profile** needs `match` and `name`. Everything else is optional, and a missing section leaves that part of the
device as macOS has it.

| Key | Value |
|---|---|
| `kind` | `"mouse"` or `"keyboard"`. Only a keyboard can host the hyper key. Leave it out and the device's interfaces decide, which makes a mouse that sends keys look like a keyboard |
| `rules` | List of rules, below |
| `gestures` | `fire`: `"pastDistance"` (fires once the hand moves `distance` sensor counts) or `"onRelease"` (fires when the button is let go). `distance`: 20 to 2000, default 120 |
| `scrolling` | Below |
| `hyper` | `true` makes the hyper key work on this keyboard |

### Rules

A rule is `{ "control": …, "when": …, "do": … }`. Only these combinations work; the app rejects any other.

| Control | `when` | `do` |
|---|---|---|
| `{ "hidpp": "0xC3" }`, a Logitech HID++ control | `click`, or `holdMoveUp` / `Down` / `Left` / `Right` | a system action, a shortcut, or a modifier tapped alone |
| | `hold` | a modifier or a shortcut, kept down until the release |
| | `holdMove` (any direction) | `"scroll"` |
| `"thumbWheel"` | `scroll` | `"reverse"` (reverses horizontal scrolling) |
| `{ "key": "escape" }`, a key a mouse sends | `click` | a shortcut, or a modifier tapped alone |
| | `hold` | `{ "modifier": … }` |
| `{ "button": 1 }`, a plain mouse button | `click` | a system action, a shortcut, or a modifier tapped alone |
| | `hold` | a modifier or a shortcut, kept down until the release |
| | `holdMove` | `"scroll"` |

- **Plain buttons** are numbered as macOS numbers them: 1 right, 2 middle, 3 back, 4 forward, up to 31. The left
  button, 0, cannot have rules.
- **System actions:** `"missionControl"`, `"appExpose"`, `"spaceLeft"`, `"spaceRight"`.
- **Shortcuts:** `{ "shortcut": "shift+cmd+4" }`. Modifiers, in any order and any case: `ctrl`/`control`,
  `opt`/`option`/`alt`, `shift`, `cmd`/`command`. The last part is the key.
- **Modifiers:** `{ "modifier": "rightOption" }` with `leftControl`, `leftShift`, `leftOption`, `leftCommand`,
  `rightControl`, `rightShift`, `rightOption` or `rightCommand`. On a key a mouse sends, `hold` maps it at the HID
  layer, so it works in password fields too. On a button, `hold` keeps it down while the button is held, so a click
  meanwhile is modified, and `click` taps it once.
- **Plain buttons other than the right one** (2 to 4) never fire their rules yet: macOS does not say which mouse sent
  them. Give a Logitech mouse's buttons their `hidpp` control instead.
- **Key names:** `a` to `z`, `0` to `9`, `return`, `escape`, `delete`, `tab`, `space`, `minus`, `equal`,
  `leftBracket`, `rightBracket`, `backslash`, `semicolon`, `quote`, `grave`, `comma`, `period`, `slash`, `capsLock`,
  `f1` to `f12`, `home`, `pageUp`, `forwardDelete`, `end`, `pageDown`, `left`, `right`, `up`, `down`.
- **One rule per control and `when`.** A control with `holdMove` cannot also have `holdMoveUp`-style swipes, since
  both read the same movement. A control with a `hold` rule holds its keys from the press, so it cannot also have a
  `click`, `holdMove` or swipe rule.
- With a `holdMove` scroll rule, a quick press of a plain button still clicks as usual. On a HID++ control a quick
  press does nothing unless the control also has a `click` rule.

### Scrolling

| Key | Value |
|---|---|
| `smooth` | Smooth scrolling for the main wheel. `duration` 1 to 20 (tenths of a second each step glides), `brake` 0.5 to 10 (higher stops harder first), `easeIn` 0 to 300 ms (default 60), and `curve` |
| `smooth.curve` | How far the page moves for how fast the wheel spins: 2 or more points of `stepsPerSecond` (1 to 150, strictly rising) and `pointsPerSecond` (10 to 30000, never falling), joined on log scales. To scroll faster overall, multiply every `pointsPerSecond` by the same factor. The default is 1→40, 5→250, 15→900, 40→2800, 120→9000 |
| `holdToScroll` | How a `holdMove` scroll rule scrolls. `speed` 0.25 to 4 (1 follows the hand), `direction` `"grab"` (the page moves with the hand) or `"wheel"` (moving down scrolls down), `momentum` true or false |
| `hiResWheel`, `clickThrough` | Accepted and saved, but they do nothing yet. Do not offer them as a fix |

## Recipes

- **New mouse with no profile:** add `{ "match": …, "name": "…", "rules": [] }` and the rules the user wants. For a
  mouse that sends keys from a keyboard interface, add `"kind": "mouse"`.
- **Hyper key on another keyboard:** add `"hyper": true` to its profile, or a new profile
  `{ "match": …, "name": "…", "hyper": true }`.
- **Turn the hyper key off everywhere:** set `"hyper": { …, "enabled": false }`.
- **Hold a button to scroll:** a `holdMove` → `"scroll"` rule on it, plus `scrolling.holdToScroll` if the user wants
  a different speed or direction.
- **Hold a button as a key (push-to-talk, ⌘-click):** a `hold` rule with `{ "modifier": "rightOption" }` or
  `{ "shortcut": "ctrl+opt+space" }`. It replaces any `click` or `holdMove` rule on that button.
- **Stop listing a device:** move its match into `ignored` and remove its profile.

## Rules of thumb

- Never add keys the app does not know or set a key to `null`: both make the app reject the whole file. Leave an
  optional key out instead.
- Keep `version` at `1` and keep the user's other devices and rules.
- When a request is ambiguous (which button, which keyboard), ask before editing.
- If the checker and the app ever disagree, the app is right: read the error from its menu or Settings › General.
