# Mouse keys

A mouse that sends keys from a keyboard interface, like the 2.4G mouse (USB, `0x1EA7:0x0002`), can have key rules. With the 2.4G preset, holding its Escape button holds Right Option, and clicking its Return button sends ⌥⇧S.

## Sub-features

- `keys-map` writes `UserKeyMapping` on the mouse's keyboard service only, never its pointer service.
- `keys-hold` maps Escape straight to Right Option at the HID layer, so the modifier is real and works in secure input.
- `keys-click` maps Return to a carrier (F13), which the tap turns into one ⌥⇧S per press. Repeats and the release reach no app.
- `keys-quit` clears the mapping on quit and pause.

## How to get to it (user POV)

- Set Up the 2.4G mouse from its preset on the Devices tab, or keep the owner's existing profile.
- Hold the mouse's Escape button and click, or press another key. Click the mouse's Return button.

## Driving it with verify.sh

Preconditions:

- The 2.4G mouse plugged in, and a profile for it with the preset's rules (the owner's file has one).
- Hyperpoint running and settled; HyperpointProbe has Accessibility; Karabiner-Elements not running.

- **Mapping applied.** Run `verify.sh state`. The 2.4G section lists two services. The keyboard service (primary usage 6 in `hidutil list`) holds `Src = 30064771113` (Escape 0x700000029) → `Dst = 30064771302` (Right Option 0x7000000E6) and `Src = 30064771112` (Return 0x700000028) → `Dst = 30064771176` (F13 0x700000068). The pointer service shows `(null)`.
- **Keys reach apps as intended.** Start `verify.sh record keys-120` in the background, so the timing does not depend on when the user reads the instructions. Ask the user to hold one of the mouse's two top buttons for about two seconds, three times, then click the other one three times and hold it for two seconds, and to say when done. The owner thinks of these as mouse buttons, not keys: say "top buttons", not Escape and Return. In the summary:
  - `in flags rightOption … flags=opt+rOpt` and `flags=-` pairs from the mouse's keyboard service, at both stages, and a `hidSystemState flags=opt+rOpt` line per hold, show Right Option held at the HID layer. No `escape` line appears.
  - The summary prints one line per distinct event with its count. The `in down f13 repeat=0` line from the same service and the `in down s … flags=opt+shift ours=1 sender=0x0` line (the posted shortcut) both count the presses, and so does the `carbonHotkeyFired` line. The hotkey takes the event, so no `app down s` line appears. The `f13 repeat=1` and `up f13` lines appear only at the `in` stage, and no `app` line has `f13`.
- **Quit clears.** Run `verify.sh quit`. `key-maps-after-quit.txt` shows `( )` or `(null)` for both 2.4G services. Then `verify.sh launch`.

## Gotchas

- Measured on 2026-10-26: after a posted shortcut, `hidSystemState` reads opt+shift until the next hardware event (5.8 s in that run). `ActionPerformer` posts the shortcut's key events with its modifiers and nothing restores the state, so the MX top button does the same. It is not a mouse-keys failure.
- The recorder logs every key outside S, Return, Escape, the modifiers, F13 and F18 as `other`, so it does not record what the owner types meanwhile.
- The recording registers ⌥⇧S as a Carbon hotkey while it runs, so whatever app the owner binds it to does not get it during the recording.
- The mouse has no product name, so the menu and `hidutil list` show it only by vendor and product.
- A relaunch recognizes a leftover map by its F13 carrier. A map with only Escape → Right Option in it is not recognizably Hyperpoint's, so if that rule is removed while Hyperpoint is not running, Escape stays Right Option until the mouse is replugged.
