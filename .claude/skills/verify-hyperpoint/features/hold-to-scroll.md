# Hold to scroll

Holding the MX Master 3's right button and moving the mouse scrolls instead of moving the pointer. The pointer stays where the button went down, the page follows the hand on both axes, and on release it glides on with trackpad momentum. A quick press is still the ordinary right click, and its menu opens at the pointer. The right button is plain button 1, which the MX cannot divert, so the event tap does all of it.

Any button can take the action: a rule with When "Hold and move" and Do "Scroll". An HID++ control such as the top button (0xC4) does it over raw movement. The MX Master 3 preset gives it to the right button only, because the user found holding the top button to scroll weird.

## Sub-features

- `hold-click` keeps the right click: a quick press opens the context menu at the pointer.
- `hold-scroll` scrolls past the profile's gesture distance, both axes, in the configured direction and speed.
- `hold-freeze` keeps the pointer where the button went down, from the press, and frees it on release.
- `hold-glide` continues the release speed with momentum phases, using the wheel glide's duration and brake.
- `hold-plain` holds back the press until it is released or moves, so apps see no drag.
- `hold-reconnect` keeps all of it after a power cycle.

## How to get to it (user POV)

- Hold the right button and move the mouse over a scrollable window.
- A quick press of the right button.
- Buttons tab: a rule with When "Hold and move" and Do "Scroll". Scrolling tab: the Hold to scroll section (speed, direction, momentum).

## Driving it with verify.sh

Preconditions:

- MX connected, Hyperpoint running and settled, HyperpointProbe has Accessibility.
- The profile has the right-button rule `{ "control": { "button": 1 }, "when": "holdMove", "do": "scroll" }`. The MX Master 3 preset gives it, and a file written before hold to scroll gets it from its `rightButtonPan` key.
- A window that scrolls both ways (a long web page or a large image) and one with a context menu, such as a Finder window.

- **Setup on device.** Run `verify.sh state`. The right button is `cid=0x51 diverted=no`, since it is handled in the tap. The top button has no scroll rule by default, so it is `cid=0xC4 diverted=yes rawXY=no`.
- **The journey.** Run `verify.sh record hold`, then ask the user, with pauses of 2 s between steps:
  1. Quick press of the right button over a Finder window. The context menu opens at the pointer. `button events apps saw` has one replayed `down` and one replayed `up` for button 1, no native ones, and both at the pointer's position before the press.
  2. Hold the right button, drag slowly down, then up, then sideways, and let go while still. The summary shows a scroll with `hand frames>0`, `ended=True`, `pointer-drift=0pt`, `glide frames=0`, and no `drag` events for button 1.
  3. Hold the right button, flick down fast and let go while moving. Repeat five times. Every scroll has `pointer-drift=0pt`, `glide frames>0` and `glide-ended=True`.
- **Direction and speed.** Switch "Like the scroll wheel" on the Scrolling tab and repeat step 2: the sign of `dy` flips for the same hand movement. Set the speed to 2×: `dy` for the same movement roughly doubles.
- **Reconnect.** Ask the user to switch the mouse off, wait 3 s, switch it on, then repeat steps 1 and 2. `verify.sh state` matches the first step.
- **Feel.** Ask whether the page follows the hand at 1× and whether the glide's length feels right. Record their words. Feel is the user's verdict, and the numbers explain it.

## Gotchas

- The posted scrolls carry the synthetic marker, so `ours=1` lines are Hyperpoint's. A trackpad scroll during the recording shows as `ours=0`.
- A right click now opens its menu on release, not on press. That is the design, because the press has to wait to see whether the hand moves.
- `pointer-drift` is measured only while the hand scrolls. The pointer is free again during the glide, so it can move then.
- The glide uses the profile's smooth-scrolling duration and brake, or the defaults when smooth scrolling is off.
- The probe's hold tap is active and passes every event through. A listen-only tap gets no hardware events without Input Monitoring, which the probe does not have.
- If the pointer ever stays frozen after a hold, quit through `verify.sh quit` (the quit path frees it) and report the steps that led there.
