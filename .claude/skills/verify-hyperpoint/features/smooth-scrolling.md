# Smooth scrolling

Wheel steps from a device whose profile has `scrolling.smooth` become continuous pixel scrolling with an eased start and a glide. Speed follows the profile's speed curve: scroll speed as a function of spin rate. The trackpad, the thumb wheel, modifier scrolls and other mice pass through untouched.

## Sub-features

- `scroll-attribution` takes only wheel events whose sender id belongs to the profile's device.
- `scroll-curve` sizes each step from the curve at the current spin rate, counting every detent in a flick.
- `scroll-glide` eases in from rest, decays after the last step, and ends without a crawl.
- `scroll-frames` times frames from the display under the pointer.
- `scroll-passthrough` leaves continuous, horizontal, modifier-held and other-device scrolls alone.

## How to get to it (user POV)

- Scroll the MX main wheel in any app (Telegram and a browser are the ones the user checks).
- Scrolling and clicks tab of the MX page in Settings, the speed graph and the glide sliders.

## Driving it with verify.sh

Preconditions:

- MX connected, Hyperpoint running and settled, HyperpointProbe has Accessibility.
- The user is at the Mac and can scroll on request.

- **Attribution.** Run `verify.sh record senders`, and ask the user to scroll the MX, then the trackpad. The MX's scrolls carry its event service id (see `verify.sh log`, `services=[0x…]`). The trackpad's carry a different id.
- **Posted frames.** Run `verify.sh record posted`, and ask the user: five single steps 2 s apart, then a 5 s slow roll, then a 5 s medium roll. In the summary: `leaked-line-events=0`; frame gaps at the display period (8.33 ms built-in, 16.67 ms external) with no alternating 13/4 ms; glides starting near zero (`0 0 1 1 …`); zero runs of 2+ empty frames between moves.
- **Input rates.** Run `verify.sh record wheel` with the same sequence plus one flick. The bursts give the user's real spin rates; compare them with the curve points.
- **Pass-through.** During `record posted`, ask for a two-finger trackpad scroll. Its events appear as continuous events that are not ours, with the user's own deltas.
- **Feel.** Ask the user how single steps, slow rolls and flicks feel, and record their words. Feel is the user's verdict; the numbers only explain it.

## Gotchas

- Apps read `scrollingDeltaY` from the integer point field only (measured). A sub-point fixed-point value does not reach them, so whole-point frames are expected.
- Synthetic test scrolls carry no MX sender id and are correctly ignored. Do not use them to prove smoothing.
- Free-spin flicks send up to 3 detents per event at about 120 events per second. macOS's line delta is accelerated and must not be read as a detent count.
- Moving the pointer between displays changes the frame period; check both if the user has two screens.
