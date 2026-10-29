# Hyper key

Holding Caps Lock on a keyboard whose profile has `"hyper": true` acts as ⌘⌃⌥⇧ held, so global shortcuts bound to the hyper chord fire. Tapping it alone does nothing. Quitting or pausing Hyperpoint gives Caps Lock back.

## Sub-features

- `hyper-map` maps Caps Lock to Right Control on each hyper keyboard's own HID service.
- `hyper-chord` turns Right Control held, on any keyboard, into ⌘⌃⌥⇧ for keys pressed meanwhile.
- `hyper-clean` leaves no modifier (or Fn) held after release.
- `hyper-switch` turns the hyper key off on every keyboard from one switch, and back on with each keyboard's own setting.
- `hyper-quit` clears the mapping on quit and pause.
- `hyper-crash` clears a hyper or carrier mapping left by a crashed run on the next launch when hyper is off.
- `hyper-secure` in secure input (a terminal's hidden prompt, a password field), where the tap sees no keys, every
  key with Control is a Carbon hotkey: with Right Control it goes on with ⌘⌃⌥⇧, letters included, and with Left
  Control it goes back to the prompt as itself.

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

- **Mapping applied.** Run `verify.sh state`. Each hyper keyboard's service shows `HIDKeyboardModifierMappingSrc = 30064771129` (Caps Lock 0x700000039) and `Dst = 30064771300` (Right Control 0x7000000E4).
- **Chord fires.** Run `verify.sh hyper-check 8`. Expect `fired 8/8, modifiers stuck after 0/8`.
- **Chord fires in secure input.** Run `verify.sh hyper-check 8 secure`. Expect `fired 8/8, modifiers stuck after
  0/8`, and `verify.sh log 2m` shows `hyper with key 106 sent on past secure input` once per run (none for the plain
  check).
- **Letters, and Left Control.** Run `verify.sh hyper-letters`, then `verify.sh hyper-letters secure`. Expect four
  `PASS` lines each. The secure run's log (`hyper-letters-secure-log.txt`) shows the Control keys taken, `hyper with
  key 50 sent on` twice and `control with key 50 given back to the app` once.
- **No Fn left held.** After `hyper-check`, run `swift -e 'import CoreGraphics; print(String(CGEventSource.flagsState(.combinedSessionState).rawValue, radix: 16))'`. Expect no 0x800000 (Fn) and none of 0x1E0000 (⌘⌃⌥⇧).
- **One switch.** With the user's consent, save their config to the evidence directory, then run `verify.sh menu "Hyper Key"`. The file has `"enabled" : false` under `hyper`, every profile keeps its `hyper` flag, and `verify.sh state` shows `( )` for both keyboards. Run it again: `enabled` is back to `true` and both mappings return. `cmp` the file with the saved copy, apart from the new `enabled` key if the saved copy had none.
- **Quit clears.** Run `verify.sh quit`. `key-maps-after-quit.txt` shows `( )` or `(null)` for both keyboards. Then `verify.sh launch`.
- **Real key.** Ask the user to hold Caps Lock and press one Raycast hyper shortcut on each keyboard, then tap Caps Lock alone. Record their answer in the evidence directory.

## Gotchas

- While Karabiner runs, the mapping is set but has no effect; `hyper-check` still passes because it posts Right Control directly. Only the real-key step proves the keyboard path.
- The Magic Keyboard matches two services; one shows `(null)`. Only the keyboard service needs the mapping.
- Secure input hides every key from event taps, and macOS gives hotkeys in it only keys that type no character or
  that are held with ⌘ or ⌃ (measured 2026-10-28 with posted keys). That is why hyper's key is Right Control, a real
  modifier: Caps Lock with T arrives as ⌃T, which a hotkey still gets. Ghostty turns secure input on for every hidden
  prompt (`macos-auto-secure-input`).
- Hyperpoint takes the Control keys up to 100 ms after secure input starts. A hyper chord pressed sooner reaches the
  prompt as ⌃ with that key.
- A shortcut that only types a character, such as the 2.4G Return's ⌥⇧S, is not sent in secure input: no hotkey
  would get it, so it would type into the password.
- A `CGEventSource` gives each new event the flags of the last event posted from it, Fn included, so an F16 check
  left the next hyper backtick carrying Fn, and its hotkey missed. Every posted key now gets a fresh source.
- Hyper with a click is a Control-click: the tap changes key events only.
- The hotkey tests use ⌘⌃⌥⇧F16 and ⌘⌃⌥⇧`. Hyper T brought Ghostty forward when the letters check used it, so the
  check avoids it. If another app ever registers one of them, `RegisterEventHotKey` fails and the count is 0.
- macOS gives way to the app the user is in, so `hyper-letters` may need Accessibility to bring its window forward,
  and it stops if the user takes the keyboard back meanwhile.
