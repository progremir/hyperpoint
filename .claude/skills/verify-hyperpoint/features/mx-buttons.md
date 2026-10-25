# MX buttons and gestures

The MX Master 3's gesture button, top button and thumb wheel follow the device's profile rules. Click → Mission Control, hold and move down → App Exposé, hold and move left/right → switch Space, top button click → ⇧⌘4, thumb wheel → horizontal scroll reversed. Hold to scroll is on the right button ([Hold to scroll](./hold-to-scroll.md)). Every connect, wake and reconfigure request writes the whole setup again.

## Sub-features

- `mx-discover` reads the mouse's feature table and controls from the device.
- `mx-divert` sets each control's reporting flags from the rules (0x33 for a control that swipes or scrolls, 0x23 for click only, 0x22 native).
- `mx-gesture` recognizes click and hold-and-move in both fire modes.
- `mx-actions` posts the user's own Mission Control, App Exposé and Space shortcuts.
- `mx-thumb` reverses the thumb wheel in firmware.
- `mx-reconnect` re-applies after a power cycle or BLE reconnect.
- `mx-neutral` returns every control to native on pause and quit.

## How to get to it (user POV)

- Use the gesture button, the top button and the thumb wheel.
- Switch the mouse off and on.
- Buttons tab of the MX Master 3 page in Settings.
- Pause or Quit from the menu.

## Driving it with verify.sh

Preconditions:

- MX Master 3 connected over Bluetooth; BetterMouse not running (`doctor` shows conflicts).
- Hyperpoint running and settled.

- **Setup on device.** Run `verify.sh state`. With the user's profile or the MX Master 3 preset: `cid=0xC3 diverted=yes rawXY=yes`, `cid=0xC4 diverted=yes rawXY=no` (it only clicks), every other control `diverted=no`, `thumbwheel diverted=no inverted=yes`.
- **Applied log.** Run `verify.sh log 5m`. A `discovered #N MX Master 3 controls=[…]` line and `hidpp #N MX Master 3 reasons=… applied` follow each connect.
- **Gestures.** Ask the user to click the gesture button, hold and move down, left and right, press the top button, and roll the thumb wheel. Record which action each produced. The top button's ⇧⌘4 fires on press.
- **Reconnect.** Ask the user to switch the mouse off, wait 3 s, switch it on, then click the gesture button. `verify.sh log 2m` shows `disconnect`, `connect`, `discovered` and `hidpp … reasons=connected … applied`. `verify.sh state` matches the first step again.
- **Neutral on quit.** Run `verify.sh quit`, then `verify.sh state`. Every control shows `diverted=no`, and the thumb wheel `inverted=no`. Then `verify.sh launch` and `verify.sh state` matches the first step.

## Gotchas

- If BetterMouse ran earlier and quit, it leaves controls diverted with no listener, so buttons are dead until Hyperpoint applies.
- macOS's own ⇧⌘4 screenshot shortcut is disabled on this Mac (symbolic hotkey 30). The top button's ⇧⌘4 only does something if another app owns it.
- After a reconnect the HID event service can appear a moment after the device. A `services=[]` connect line followed by a service line is normal.
- The thumb wheel invert is firmware state. A power cycle resets it until Hyperpoint re-applies.
