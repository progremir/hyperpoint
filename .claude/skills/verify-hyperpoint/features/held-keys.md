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
Tell the owner what the journey checks before asking for presses, and use a short recording started right after they
say they are at the mouse: the first two 3- and 4-minute recordings on 2026-10-26 caught no press at all.

1. Add to the MX profile `{ "control": { "hidpp": "0x56" }, "when": "hold", "do": { "modifier": "leftShift" } }`
   (Forward) and `{ "control": { "hidpp": "0x52" }, "when": "hold", "do": { "shortcut": "ctrl+opt+cmd+h" } }` (Middle).
   For the plain-button path, swap the right button's hold-to-scroll rule for
   `{ "control": { "button": 1 }, "when": "hold", "do": { "modifier": "leftCommand" } }`.
2. **Diverts.** `verify.sh state` shows 0x52 and 0x56 `diverted=yes rawXY=no flags=0x01`.
3. **What apps get.** Start `verify.sh record held-60` in the background once the owner is ready. Ask them to hold
   Forward and left-click empty desktop, let go; hold the wheel down for about 2 s, let go; and with the plain rule,
   hold the right button and left-click empty desktop, let go. Empty desktop, because a ⌘- or ⇧-click on a file or a
   link does something. In `record-held-60.txt`:
   - Forward: `flags key=56 … flags=shift+lShift ours=1`, `hidSystemState flags=shift+lShift` that stays until the
     release, an `app leftDown … flags=shift+lShift` click, then `flags key=56 flags=- ours=1`.
   - Middle: `flags key=59`, `58`, `55`, `down key=4`, `hotkey ctrl+opt+cmd+H pressed`, and about 2 s later `up key=4`
     before the three modifiers go up in reverse, then `hotkey ctrl+opt+cmd+H released`.
   - The right button: `flags key=55 … flags=cmd+lCmd ours=1`, an `app leftDown … flags=cmd+lCmd`, no `app rightDown`.
4. **No lag.** `swift tools/taps.swift` lists Hyperpoint's main tap with a small latency and the overlay tap
   (mask 0xe401cfe) `enabled=false` once nothing is held.
5. Restore the owner's config, `cmp` it, and check `verify.sh state` matches the baseline.

## Gotchas

- Measured on 2026-10-26: Forward held as Shift made both clicks in the holds ⇧-clicks, and the wheel's ⌃⌥⌘H was
  pressed for the 2 s it was held. Before the overlay, `hidSystemState` dropped Shift 20 ms after the press, under the
  hand's own movement, and the click came without it.
- Before `OverlaySwitch`, turning the overlay off sent it a notice it answered by turning itself off again, and the
  tap thread spun: Hyperpoint's taps answered after seconds and the owner's input lagged until `verify.sh quit`. If keys
  or clicks lag during this journey, quit Hyperpoint first, then look at `tools/taps.swift`.
- An other-button press carries no sender (`sender=0x0` in the recording), so a plain-button rule on the middle, back or
  forward button never fires. Use the right button for the plain path, and the MX's buttons as HID++ controls.
- The recording registers ⌃⌥⌘H as a Carbon hotkey, so the front app does not get it during the recording.
- Secure input disables keyboard event taps, but neither path reads keys: a plain button comes through the tap as a
  mouse event and a HID++ control over HID++. Whether a held modifier reaches a secure text field is unmeasured.
