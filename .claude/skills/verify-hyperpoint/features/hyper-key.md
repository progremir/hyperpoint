# Hyper key

Holding Caps Lock on a keyboard whose profile has `"hyper": true` acts as ⌘⌃⌥⇧ held, so global shortcuts bound to the hyper chord fire. Tapping it alone does nothing. Quitting or pausing Hyperpoint gives Caps Lock back.

## Sub-features

- `hyper-map` maps Caps Lock to F18 on each hyper keyboard's own HID service.
- `hyper-chord` turns F18 held into ⌘⌃⌥⇧ for keys pressed meanwhile.
- `hyper-clean` leaves no modifier (or Fn) held after release.
- `hyper-switch` turns the hyper key off on every keyboard from one switch, and back on with each keyboard's own setting.
- `hyper-quit` clears the mapping on quit and pause.
- `hyper-crash` clears a carrier mapping left by a crashed run on the next launch when hyper is off.

## How to get to it (user POV)

- Hold Caps Lock and press a key bound to ⌘⌃⌥⇧ in another app (the user's Raycast hyper bindings).
- Tap Caps Lock alone.
- Hyper key page in Settings: the Hyper key switch at the top, and per-keyboard switches.
- The Hyper Key item in the menu bar menu.
- Pause Hyperpoint or Quit from the menu.

## Driving it with verify.sh

Preconditions:

- Hyperpoint running and settled; HyperpointProbe has Accessibility.
- For the real-key check only: Karabiner-Elements quit by the user (it seizes keyboards).

- **Mapping applied.** Run `verify.sh state`. Each hyper keyboard's service shows `HIDKeyboardModifierMappingSrc = 30064771129` (Caps Lock 0x700000039) and `Dst = 30064771181` (F18 0x70000006D).
- **Chord fires.** Run `verify.sh hyper-check 8`. Expect `fired 8/8, modifiers stuck after 0/8`.
- **No Fn left held.** After `hyper-check`, run `swift -e 'import CoreGraphics; print(String(CGEventSource.flagsState(.combinedSessionState).rawValue, radix: 16))'`. Expect no 0x800000 (Fn) and none of 0x1E0000 (⌘⌃⌥⇧).
- **One switch.** With the user's consent, save their config to the evidence directory, then run `verify.sh menu "Hyper Key"`. The file has `"enabled" : false` under `hyper`, every profile keeps its `hyper` flag, and `verify.sh state` shows `( )` for both keyboards. Run it again: `enabled` is back to `true` and both mappings return. `cmp` the file with the saved copy, apart from the new `enabled` key if the saved copy had none.
- **Quit clears.** Run `verify.sh quit`. `key-maps-after-quit.txt` shows `( )` or `(null)` for both keyboards. Then `verify.sh launch`.
- **Real key.** Ask the user to hold Caps Lock and press one Raycast hyper shortcut on each keyboard, then tap Caps Lock alone. Record their answer in the evidence directory.

## Gotchas

- While Karabiner runs, the mapping is set but has no effect; `hyper-check` still passes because it posts F18 directly. Only the real-key step proves the keyboard path.
- The Magic Keyboard matches two services; one shows `(null)`. Only the keyboard service needs the mapping.
- Hyper is lost in password fields (secure input disables key taps). That is expected, not a failure.
- The hotkey test uses ⌘⌃⌥⇧F16. If another app ever registers it, `RegisterEventHotKey` fails and the count is 0.
