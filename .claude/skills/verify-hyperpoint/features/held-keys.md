# Held keys

A mouse button with a `"when": "hold"` rule holds a modifier, or a shortcut's modifiers and key, from its press to its
release. A HID++ control (the MX's Back, Forward, Middle, gesture and top buttons) is diverted without raw movement
and its press arrives over HID++. A plain button (any mouse's right, middle, back and forward buttons the MX does not
divert) is seen in the tap. Both hand the hold to the tap thread, which posts marked key events at the HID tap.

## Sub-features

- `held-divert` diverts a HID++ control with a hold rule without raw movement (flags 0x01), so the pointer moves.
- `held-modifier` holds one modifier: a left click meanwhile is a modified click, and a key on the keyboard carries it.
- `held-shortcut` presses a shortcut's modifiers, then its key, on the press, and lets go in reverse on the release.
- `held-plain` does the same for a plain button, whose drags reach apps as plain pointer movement.
- `held-release` lets go on the release, and on an apply, a device going away, pause and quit while still held.

## How to get to it (user POV)

- Buttons tab, a rule's **When** set to **Hold**, and **Do** set to a modifier or to **Keyboard Shortcut…**.
- Hold the button, click or type, let go.

## Driving it with verify.sh

Preconditions: Hyperpoint running and settled; HyperpointProbe has Accessibility; the MX connected. The journey edits
the config, so save the owner's file to the evidence directory first and restore it byte for byte (`cmp`) at the end.

1. Add to the MX profile `{ "control": { "button": 3 }, "when": "hold", "do": { "modifier": "leftCommand" } }` (Back,
   the plain path), `{ "control": { "hidpp": "0x56" }, "when": "hold", "do": { "modifier": "leftShift" } }` (Forward,
   the HID++ path) and `{ "control": { "hidpp": "0x52" }, "when": "hold", "do": { "shortcut": "ctrl+opt+cmd+h" } }`
   (Middle, a shortcut).
2. **Diverts.** `verify.sh state` shows 0x52 and 0x56 `diverted=yes rawXY=no flags=0x01`, and 0x53 not diverted.
3. **What apps get.** Start `verify.sh record held-180` in the background, then ask the owner to: hold Back, move the
   pointer, left-click empty desktop, let go; hold Forward, left-click empty desktop, let go; hold the wheel down for
   about 2 s, let go; tap Back once. In `record-held-180.txt`:
   - Back: an `in flags key=55 … flags=cmd+lCmd ours=1` line after the `in otherDown button=3`, no `app otherDown`,
     `app moved` lines while it is held, an `app leftDown … flags=cmd+lCmd` click, then `flags key=55 flags=- ours=1`
     on the release with no `app otherUp`. `hidSystemState flags=cmd+lCmd` while held, `-` after.
   - Forward: the same with `key=56 … flags=shift+lShift`, and no `otherDown` at either stage, since HID++ takes it.
   - Middle: `flags key=59`, `flags key=58`, `hotkey ctrl+opt+cmd+H pressed`, then about 2 s later
     `hotkey ctrl+opt+cmd+H released` and the modifiers going up in reverse.
   - The quick tap of Back holds and lets go with nothing in between.
4. **Release on an interruption.** Hold Forward and, while holding it, have the config saved (any change from the
   settings window). `hidSystemState` goes back to `-` while the button is still down.
5. Restore the owner's config, `cmp` it, and check `verify.sh state` matches the baseline.

## Gotchas

- Not yet run with a press: the owner deferred it on 2026-10-26. The diverts in step 2 were read back that day.
- The recording registers ⌃⌥⌘H as a Carbon hotkey, so the front app does not get it during the recording.
- Secure input disables keyboard event taps, but neither path reads keys: a plain button comes through the tap as a
  mouse event and a HID++ control over HID++. Whether a posted modifier reaches a secure text field is unmeasured.
