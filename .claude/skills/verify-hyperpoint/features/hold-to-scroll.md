# Hold to scroll

A button with the rule hold and move → scroll turns mouse movement into scrolling while it is held. The pointer stays put, the page follows the hand on both axes, and on release it glides on with trackpad momentum. A quick press still does the button's click rule, or for a plain button the ordinary click. On the MX Master 3 the top button (0xC4) does it over HID++ raw movement, and the right button (plain button 1, which the MX cannot divert) does it in the event tap.

## Sub-features

- `hold-divert` diverts a HID++ control with a scroll rule with raw movement (flags 0x33).
- `hold-click` keeps the click: the top button's ⇧⌘4, the right button's context menu.
- `hold-scroll` scrolls past the profile's gesture distance, both axes, in the configured direction and speed.
- `hold-freeze` keeps the pointer where the hold began while scrolling, and frees it on release.
- `hold-glide` continues the release speed with momentum phases, using the wheel glide's duration and brake.
- `hold-plain` holds back a plain button's press until it is released or moves, so apps see no drag.
- `hold-reconnect` keeps all of it after a power cycle.

## How to get to it (user POV)

- Hold the top button, or the right button, and move the mouse over a scrollable window.
- A quick press of either button.
- Buttons tab: a rule with When "Hold and move" and Do "Scroll". Scrolling and clicks tab: the Hold to scroll section (speed, direction, momentum).

## Driving it with verify.sh

Preconditions:

- MX connected, Hyperpoint running and settled, HyperpointProbe has Accessibility.
- The profile has the scroll rules. A new file gets them from `Config.default`. A file written before hold to scroll gets the right-button rule from its `rightButtonPan` key, but not the top-button one. Add `{ "control": { "hidpp": "0xC4" }, "when": "holdMove", "do": "scroll" }` with the user, after saving their file to the evidence directory.
- A window that scrolls both ways (a long web page or a large image) and one with a context menu, such as a Finder window.

- **Setup on device.** Run `verify.sh state`. With a top-button scroll rule: `cid=0xC4 diverted=yes rawXY=yes`. Without one: `diverted=yes rawXY=no` (click only). The right button is `cid=0x51 diverted=no`, since it is handled in the tap.
- **The journey.** Run `verify.sh record hold`, then ask the user, with pauses of 2 s between steps:
  1. Quick press of the top button. ⇧⌘4 fires (another app must own it, see mx-buttons gotchas). The recording shows no scroll.
  2. Hold the top button, move slowly down, then up, then sideways, and let go while still. The summary shows a scroll with `hand frames>0`, `ended=True`, `pointer-drift=0pt` and `glide frames=0`.
  3. Hold the top button, flick down and let go while moving. The same, plus `glide frames>0` and `glide-ended=True`.
  4. Quick press of the right button over a Finder window. The context menu opens. `button events apps saw` has one replayed `down` and one replayed `up` for button 1 and no native ones.
  5. Hold the right button and drag. The page scrolls, with no `drag` events for button 1 in the summary, `pointer-drift=0pt`, and a glide if the user let go while moving.
- **Direction and speed.** Switch "Like the scroll wheel" on the Scrolling and clicks tab and repeat step 2: the sign of `dy` flips for the same hand movement. Set the speed to 2×: `dy` for the same movement roughly doubles.
- **Reconnect.** Ask the user to switch the mouse off, wait 3 s, switch it on, then repeat steps 1, 2 and 4. `verify.sh state` matches the first step.
- **Feel.** Ask whether the page follows the hand at 1× and whether the glide's length feels right. Record their words. Feel is the user's verdict, and the numbers explain it.

## Gotchas

- The posted scrolls carry the synthetic marker, so `ours=1` lines are Hyperpoint's. A trackpad scroll during the recording shows as `ours=0`.
- A right click now opens its menu on release, not on press. That is the design, because the press has to wait to see whether the hand moves.
- `pointer-drift` is measured only while the hand scrolls. The pointer is free again during the glide, so it can move then.
- The glide uses the profile's smooth-scrolling duration and brake, or the defaults when smooth scrolling is off.
- If the pointer ever stays frozen after a hold, quit through `verify.sh quit` (the quit path frees it) and report the steps that led there.
