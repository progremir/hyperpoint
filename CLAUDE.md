# Hyperpoint

Menu-bar app replacing BetterMouse + Karabiner-Elements for one MX Master 3, one 2.4G mouse and the built-in / Magic keyboards. Re-applies every setting on each device connect.

Design doc (source of truth for scope, phases, risks): https://claude.ai/artifact/2Y5T5C7HWiWFDAEFZLWiKc

## Facts gathered during diagnosis

- MX Master 3: Bluetooth, vendor 0x046D (1133), product 0xB023 (45091). Reconnects many times a day.
- BetterMouse diverts HID++ CIDs 0xC3 (gesture button, "button 5") and 0xC4 (top button behind wheel, assumed "button 6").
- 2.4G mouse: vendor 0x1EA7 (7847), product 0x2. Its upper buttons send Escape / Return from a keyboard interface.
- Current Karabiner rules: `~/.config/karabiner/karabiner.json` (Caps Lock → ⌘⌃⌥⇧ hold, no tap action; 2.4G Escape → Right Option, Return → ⌥⇧S).
- Current BetterMouse settings: `defaults export com.naotanhaocan.BetterMouse -` (values under `mice`, `appitems` are nested binary plists).
- Signing identity for stable TCC grants: "Apple Development: Emir Amanbekov (KGBFPV5MVR)".
- Toolchain: Swift 6.4, macOS 27.0.1, arm64.
- Do not decompile BetterMouse; HID++ 2.0 is documented by Solaar and logiops.

## Tools

- `tools/taps.swift`: lists system event taps (owner, active/listen-only, enabled, mask). Run with `swift tools/taps.swift`.
