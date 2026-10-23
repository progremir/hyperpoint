# Hyperpoint architecture

Hyperpoint keeps every device it knows in the state its profile describes, and it puts that state back whenever a device forgets it. A device forgets often. HID++ button diverts are lost on sleep and reconnect, a `hidutil` key mapping dies with its HID service, and macOS disables an event tap that answers slowly. So the app has one job, which it does the same way for every trigger. It computes the desired state from the config and writes all of it, absolutely, to each device.

This document is the design for v1 and v2 together. The UI it serves is the canvas at https://claude.ai/artifact/J1cMdDRx2pMYBM8KfsV7JY. Platform facts and their sources are in [Appendix A](#appendix-a-platform-facts).

## Problem

Three things make the shape non-obvious.

- **Devices are open-ended.** The settings window lists every device Hyperpoint has seen. The MX Master 3 and the 2.4G mouse are two cases of one model, and an unknown mouse can appear and get rules. What a device can do depends on what it is. A Logitech device speaks HID++ and exposes divertable controls. Other mice send keys from a keyboard interface, or plain buttons. Keyboards can host the hyper key.
- **State lives in three places that forget independently.** These are HID++ firmware state on the device, `UserKeyMapping` on each HID service, and the rules inside the event tap.
- **Two hot paths must stay O(1).** HID++ notifications arrive on every gesture-button movement, and every key and click on the Mac passes through the event tap.

## Usage

### The config file

`~/.config/hyperpoint/config.json` is the single source of truth. The settings window edits this file and nothing else. This is the default file, which reproduces today's BetterMouse and Karabiner setup.

```json
{
  "version": 1,
  "hyper": { "key": "capsLock", "onTap": "nothing" },
  "devices": [
    {
      "match": { "vendor": "0x046D", "product": "0xB023" },
      "name": "MX Master 3",
      "rules": [
        { "control": { "hidpp": "0xC3" }, "when": "click", "do": "missionControl" },
        { "control": { "hidpp": "0xC3" }, "when": "holdMoveDown", "do": "appExpose" },
        { "control": { "hidpp": "0xC3" }, "when": "holdMoveLeft", "do": "spaceLeft" },
        { "control": { "hidpp": "0xC3" }, "when": "holdMoveRight", "do": "spaceRight" },
        { "control": { "hidpp": "0xC4" }, "when": "click", "do": { "shortcut": "shift+cmd+4" } },
        { "control": "thumbWheel", "when": "scroll", "do": "reverse" }
      ],
      "gestures": { "fire": "pastDistance", "distance": 120 },
      "scrolling": {
        "smooth": { "duration": 4, "brake": 2, "acceleration": true, "speed": 40, "startBoost": 2 },
        "hiResWheel": true,
        "rightButtonPan": { "momentum": true },
        "clickThrough": { "left": true, "right": true }
      }
    },
    {
      "match": { "vendor": "0x1EA7", "product": "0x0002" },
      "name": "2.4G Mouse",
      "rules": [
        { "control": { "key": "escape" }, "when": "hold", "do": { "modifier": "rightOption" } },
        { "control": { "key": "return" }, "when": "click", "do": { "shortcut": "opt+shift+s" } }
      ]
    },
    { "match": { "builtIn": true }, "name": "Built-in Keyboard", "hyper": true },
    { "match": { "vendor": "0x004C", "product": "0x0321" }, "name": "Magic Keyboard", "hyper": true }
  ],
  "ignored": []
}
```

The rules for the file:

- A device entry is a **profile**. Its `match` names the device. Everything else is optional, and a missing section means "leave the device as macOS has it".
- A rule is `control`, `when`, `do`. Which `when` values a control accepts depends on its kind, and the parser rejects a rule that cannot work, with its path (for example `devices[1].rules[0].when`).
- An unknown key is an error with its path, so a typo cannot silently do nothing. An invalid file is rejected whole. The last good config keeps running, and the menu and settings window say what is wrong.
- `ignored` lists devices the user chose to ignore. A device with no profile and not ignored shows as new in the sidebar and is left untouched.
- Pause is runtime state, not config.

### Call site 1. The MX Master 3 connects

1. The IOHIDManager matching callback fires on the HID thread. `DeviceHub` groups the new IOHIDDevice interfaces into one `PresentDevice` and finds its profile by `match`.
2. The device has a HID++ collection, so its slot opens a `HIDPPSession`. Discovery reads the feature table and the control list (`getCount`, `getCidInfo`), which become the device's `Capabilities`.
3. `Intent.compile` turns the profile and the capabilities into a `DeviceSetup`. For the MX, that is `0xC3` as a gesture control (divert plus rawXY, flags `0x33`), `0xC4` as a press control (`0x23`), and the thumb wheel undiverted and inverted.
4. The slot's worker writes all of it and reads it back. A timeout right after a BLE connect is normal, so `RetryPolicy` retries at 0.3, 1, 2, 4 and 8 seconds.
5. The journal logs the connect and the apply, and the menu shows "MX Master 3 reconnected at 15:06. Settings re-applied."

A 0x1D4B notification with the reconfigure flag, a config save, a permission grant, wake, resume and "Re-apply Settings Now" all enter at step 3 through the same call, `slot.invalidate(reason)`.

### Call site 2. The user adds a rule by pressing a button

1. The settings window calls `engine.learn(device)`. The device's intent gains a learning overlay. For HID++ devices it temporarily diverts every divertable control. For other devices the slot listens to the device's input values with `IOHIDDeviceRegisterInputValueCallback`, which needs no seize.
2. The next press arrives as a `LearnedControl` (`.hidpp(0x56)`, `.key(.escape)` or `.button(4)`), and the engine publishes it in `EngineStatus`.
3. The window appends a rule with that control to the profile and writes the file through `ConfigStore`. The reload removes the overlay and applies the new rule through the normal path.

### Call site 3. Caps Lock is held and R is pressed

1. When a keyboard whose profile has `"hyper": true` appears, its slot sets `UserKeyMapping` on that keyboard's service only. Caps Lock (usage 0x39) becomes F18 (0x6D). The OS never sees Caps Lock, so there is no LED toggle and no caps delay.
2. F18 key-down reaches the event tap on the tap thread. `CarrierStage` finds F18 in `TapRules.carriers` as `.holdModifiers(⌘⌃⌥⇧)` and rewrites the event in place into a `flagsChanged` event with ⌘⌃⌥⇧ set. The system's modifier state now shows hyper held.
3. R key-down gets ⌘⌃⌥⇧ added to its flags.
4. F18 key-up is rewritten in place into a `flagsChanged` event with the four modifiers cleared, so the system's modifier state goes back to normal. A tap timeout or a keyboard disappearing also clears the hyper state, so hyper can never stay stuck on.

The hyper prototype chose this strategy ([Appendix B](#appendix-b-prototype-results)).

The 2.4G mouse uses the same mechanism. Its Escape maps straight to Right Option at the HID layer, so holding it is a real held modifier and it works in password fields. Its Return maps to a carrier key, which the tap rewrites to ⌥⇧S.

## Shape

### Base and grafts

This design is candidate B of a two-model architect arena, with grafts from candidate A, rebuilt for open-ended devices. [Synthesis decision](#synthesis-decision) records what came from where.

### Data structures

| Type | What it encodes |
| --- | --- |
| `Config` | The parsed file. `ConfigCodec.decode` is the only way in. The unknown-key check walks the user's JSON against the encoded types, so no key list exists to drift. |
| `DeviceProfile` | One device entry. `match`, `name`, `rules: [Rule]`, `gestures`, `scrolling`, `hyper`. |
| `DeviceMatch` | Vendor and product, or `builtIn`. One value classifies a `PresentDevice` and renders hidutil `--matching`. IOHIDManager ignores `Built-In` (measured), so Swift's `matches` is the authority and the manager is only a prefilter. |
| `Rule` | `Control`, `Trigger`, `Action`. |
| `Control` | `.hidpp(CID)`, `.thumbWheel`, `.key(HIDUsage)` for a key a mouse sends from a keyboard interface, `.button(Int)` for a plain mouse button. |
| `Trigger` | `.click`, `.hold`, `.holdMove(Direction)`, `.scroll`. |
| `Action` | `.system(SystemAction)`, `.shortcut(Chord)`, `.modifier(HeldModifier)`, `.reverse`. `SystemAction.rawValue` is the CGS symbolic hotkey id (32, 33, 79, 81), so the id table is the enum. |
| `PresentDevice` | A connected device, grouped from its IOHIDDevice interfaces. Instance id, `DeviceKey`, name, transport, the ids of its HID event services, `Capabilities`. |
| `DeviceRoster` | The registry ids of each present device's IOHIDDevice interfaces and HID event services. `DeviceHub` feeds it from IOKit, and it decides which device a newly published event service belongs to. |
| `Capabilities` | What discovery found. HID++ controls with their flags (temporary divert, rawXY), thumb wheel, keyboard interface, pointer, keyboard. Never stored in config. |
| `Intent` | `Intent.compile(config, paused, present)`. A pure function that returns a `DeviceSetup` per present device and one `TapRules`. Paused compiles to `Intent.neutral`, so pause is the same reconcile as a config change. |
| `DeviceSetup` | What lives on the device or its service. `hidpp: [CID: ControlBehavior]`, `thumbWheelInverted`, `keyMap: [KeyRoute]`. Written whole on every apply. |
| `ControlBehavior` | `.native`, `.press(Action)`, `.gesture(GesturePlan)`. The firmware flags (`0x22`, `0x23`, `0x33`) and the host routing derive from the same case, so "diverted with rawXY but not fed to the recognizer" cannot be built. |
| `KeyRoute` | One remap, from a source usage to `.native(usage)` or `.carrier(Carrier, CarrierMeaning)`. The hidutil JSON and the tap's carrier rules both derive from the same `[KeyRoute]`. |
| `Carrier` | A reserved F13 to F24 key. Hyper is F18. Key rules get carriers from the rest of the pool, assigned in a stable order by `Intent.compile`. The pool is the only place these numbers exist, as a HID usage and a virtual key code side by side. |
| `TapRules` | Carrier meanings, plus per-sender settings for scrolling, pan and click-through, keyed by the HID service ids of the devices whose profiles enable them. |
| `EngineStatus` | One immutable value the UI renders. Run state, permissions, per-device link, last apply and capabilities, new devices, learned control, last hyper chord. |

The dominant access patterns, traced through these types:

- **A HID++ notification** resolves to its slot in O(1) by device instance. `HIDPPLink` decodes it through the session's feature map and feeds the gesture machine. No allocation and no thread hop.
- **A tap event** costs one carrier lookup by key code. Scroll and button events also cost one lookup by sender id. A sender with no entry passes untouched, so the trackpad is never smoothed.
- **A config save** recompiles the intent once and invalidates every present slot. Each slot writes its whole setup. There is no diffing logic to get wrong.

### Module map

One SwiftPM library with three folders and a thin app target, built into a signed `.app` by a script.

| Path | Access | Holds |
| --- | --- | --- |
| `Sources/HyperpointKit/Model` | public | `Config` and its parts, `ConfigCodec`, `EngineStatus` |
| `Sources/HyperpointKit/Core` | internal, pure | `Intent`, `KeyRoute`, `Carrier`, HID++ codec, `HIDPPLink`, `GestureMachine`, `TapPipeline` and its stages, `ScrollAnimator`, `DeviceRoster`, `ApplyScheduler`, `RetryPolicy`, `Capabilities` |
| `Sources/HyperpointKit/Runtime` | internal, except `Engine`, `ConfigStore`, `Permissions` | executors, `DeviceHub`, `Slot`, `HIDPPSession`, `KeyMapWriter`, `TapHost`, `ActionPerformer`, `Journal` |
| `Sources/Hyperpoint` | app | `AppModel`, the menu, Welcome and settings views |

Per-layer SwiftPM targets do not stop the app importing a lower layer (measured), but access control does hide internals across the library boundary (measured). `scripts/check-layers.sh` fails the build when Core imports IOKit or anything from Runtime.

### Threading model

Each device-facing thread is a global actor whose executor is that thread's CFRunLoop. Actor isolation is then thread confinement, which the compiler checks. A C callback that fires on the run loop enters the actor synchronously with `assumeIsolated`, with no hop and no copy. Both candidates spiked this pattern on this Mac. Every C callback is a file-scope `nonisolated` function, because a closure written inside main-actor code traps on another thread (measured).

| Context | Owns |
| --- | --- |
| Main actor | `AppModel`, SwiftUI, `ActionPerformer` (symbolic hotkey lookup runs on main in Mac Mouse Fix, so Hyperpoint does the same) |
| `@HIDActor` | `Engine` (desired state), `DeviceHub` and its IOHIDManager, every `Slot`, every `HIDPPSession` and its `HIDPPLink`, `Journal` |
| `@TapActor` | `TapHost`, the mach port, `TapPipeline`, the `ScrollAnimator` instance and its glide timer, the watchdog. Nothing else ever runs here. |
| Cooperative pool | `ConfigStore` (an actor that owns the file), `KeyMapWriter` (the `hidutil` process), permission polling |

State crosses only as immutable `Sendable` values.

| From, to | Carrier | Policy |
| --- | --- | --- |
| Main to HID | `await engine.reapplyAll()`, `setPaused`, `learn`, `forget` | one hop per user action |
| HID to main | `engine.statuses` | latest wins |
| HID to main | `engine.actions` | ordered, for `ActionPerformer` |
| ConfigStore to HID and main | `store.events()` | each element is a full state |
| HID to tap | `TapRules` | latest wins, applied between events |
| Tap to HID | `TapSignal` (re-enabled, invalidated, hyper chord) | ordered, rare |

There is no lock and no shared mutable object. Config has one owner, `ConfigStore`. The engine and the UI each hold a copy of the latest value it published, and neither writes it back except through `ConfigStore.update`.

### Load-bearing decisions

1. **One reconcile path.** Every trigger calls `slot.invalidate(reason)`. `ApplyScheduler` gives each device one writer and collapses triggers that arrive mid-apply into one follow-up. Every write is absolute, so running an apply twice, or after a crash halfway, ends in the same state (per make-operations-idempotent).
2. **The HID++ conversation is a value.** `HIDPPLink` takes bytes and time and returns bytes, events and a deadline. Discovery, writes, read-back, retries, notifications, button edges and gesture recognition are all transitions on it. Tests drive it against a firmware model seeded with the measured BetterMouse state, and they assert the model's end state, not the request order (per test-behavior-not-implementation).
3. **Device identity is decided at the HID layer for keys.** `hidutil` maps keys per service, and the tap only sees carrier key codes. The tap never has to work out which keyboard sent a key. No device is seized.
4. **Pointer events are attributed by sender id.** Per-device scrolling, pan, click-through and plain-button rules need to know which mouse sent a scroll or click. The tap reads the sender id with `CGEventCopyIOHIDEvent` and `IOHIDEventGetSenderID`, as LinearMouse does, and looks it up in `TapRules`. This is private API. The prototype measured it on this Mac. The sender id is the registry id of the device's HID event service (for the MX, `AppleUserHIDEventService`), not of its `IOHIDDevice`, so `DeviceHub` records the event service ids under each `PresentDevice`. Over BLE the event service is published after the IOHIDDevice matches (measured on an MX reconnect), so `DeviceHub` also watches for new `IOHIDEventService` entries. `DeviceRoster` gives each one to the device that owns one of its registry ancestors, and the engine recompiles `TapRules`.
5. **Profiles are data, capabilities are discovered.** No device is a constant in code. The MX and 2.4G defaults are initial profile data in `Config.default`. A HID++ device's controls come from `getCidInfo`, so a different Logitech mouse works without code changes.

### Invariants and boundaries

- `KeyCode`, `HIDUsage`, `CID` and `SenderID` are distinct types (per type-system-discipline).
- HID++ wire types stay internal to Core. The runtime sees report bytes in and out, nothing else.
- Validation happens at five boundaries and nowhere else (per boundary-discipline). `ConfigCodec` for the file, the HID++ codec for device bytes, `KeyMapWriter` for `hidutil` output, `DeviceHub` for IOKit properties, and `TapHost` for CGEvents.
- `TapPipeline.reset()` runs on tap timeout and on every keyboard removal, so a lost key-up cannot leave hyper held.
- Every event Hyperpoint posts carries a marker in `eventSourceUserData`, and every stage passes marked events untouched. Hyperpoint's own ⇧⌘4 or smooth-scroll events are never rewritten.

### Gesture machine

`GestureMachine` is a pure machine with no clock. Inputs are `press(GesturePlan)`, `move(dx, dy)`, `release` and `cancel`. States are `idle`, `tracking(plan, dx, dy)` and `consumed`. The plan is captured at press, so a config edit mid-gesture cannot change a gesture in flight.

- In `pastDistance` mode, the move that makes net travel reach `distance` fires the swipe for the dominant axis. In `onRelease` mode, the release decides. Below `distance`, the release is a click.
- A swipe in a direction with no rule is consumed. It fires nothing and is not a click.
- A press while tracking means a release was lost, so the machine starts over. Device removal and every apply send `cancel`.

### v2 scrolling and clicks

All four live in `TapPipeline` as stages, each with `static let interests`. `TapPipeline.mask` is derived from the stages, never hand-listed. Their settings reach the tap as per-sender entries in `TapRules`.

- **Smooth scrolling.** `ScrollStage` drops wheel ticks from enabled senders and feeds `ScrollAnimator`, a pure velocity model driven by a timer on the tap run loop. It posts marked continuous scroll events. [Smooth scrolling](#smooth-scrolling) has the model.
- **High-resolution wheel.** HID++ feature 0x2121 adds one write and one read-back to the device setup. `ScrollStage` then treats the finer deltas as input.
- **Right-button pan.** `PanStage` holds a right-button down from an enabled sender. Drag past a few points turns it into scrolling, with momentum through `ScrollAnimator`. A release without drag replays the right click.
- **Click-through.** `ClickThroughStage` sees a click from an enabled sender on a background window and makes it act at once. How it activates the window without eating the click is open ([Open questions](#open-questions-and-risks)).

### Smooth scrolling

The MX wheel without BetterMouse sends line-based wheel events, and apps such as Telegram animate each one as a separate jump. Hyperpoint replaces those events with a glide of continuous pixel scrolls, the kind a trackpad sends.

`ScrollStage` takes a wheel event when it is line-based, vertical, has no modifier held, and comes from a sender in `TapRules.smoothScroll`. Every other scroll passes untouched. Trackpad scrolls are continuous, the thumb wheel is horizontal, shift-scroll and zoom carry a modifier, and other mice have no entry. Each taken event is one tick, and only the sign of its delta counts, so macOS's own wheel acceleration never stacks on Hyperpoint's.

`ScrollAnimator` keeps one velocity. Each tick adds an impulse to it. Between ticks the velocity falls as `(1 - t / duration) ^ brake`, so it reaches zero exactly `duration` after the last tick. A tick in the other direction ends the glide on the next frame and starts a new one. The impulse is sized to give each knob one job:

- A tick when no glide is running scrolls `startBoost` × `speed` points. This is the faster start the user asked for.
- A steady stream scrolls `speed` points per tick whatever `duration` and `brake` are, so those two shape only the glide. The boost fades as ticks come closer together, so the distance per tick has no step where a glide ends.
- With `acceleration`, ticks closer than 50 ms each scroll farther, up to 4× at 80 ticks per second.

| Key | Meaning | Default | Range |
| --- | --- | --- | --- |
| `duration` | Glide length after the last tick, in tenths of a second | 4 | 1 to 20 |
| `brake` | Exponent of the velocity decay. At 1 the glide slows evenly. Higher values brake hard first and coast into a soft stop. | 2 | 0.5 to 10 |
| `acceleration` | Ticks closer than 50 ms scroll farther | true | |
| `speed` | Points per tick in a steady stream | 40 | 1 to 500 |
| `startBoost` | Distance of a tick when no glide is running, as a multiple of `speed` | 2 | 1 to 10 |

`duration` is in tenths of a second so that BetterMouse's value of 4, whose unit is unknown, starts as a 0.4 s glide. A file without `speed` or `startBoost` gets the defaults. With the defaults, one tick scrolls 80 points over 0.4 s, 10 ticks per second scroll about 490 points per second, and 60 ticks per second about 6,000 (measured on the animator with a fake clock).

`TapHost` arms a 120 Hz run-loop timer on the tap thread when a tick starts a glide and disarms it when the animator is idle. Each frame is a new `CGEvent` in pixel units, posted at the session level with the scroll phase began, changed or ended and the synthetic marker. AppKit reads these as precise deltas with matching phases (measured). A config save sends new `TapRules`, so changed knobs apply from the next tick.

### Build setup

SwiftPM plus `scripts/bundle.sh`. The script runs `check-layers.sh`, builds release, assembles `Hyperpoint.app` with an `LSUIElement` `Info.plist`, and signs it with "Apple Development: Emir Amanbekov (KGBFPV5MVR)" and a fixed identifier. It then checks that the designated requirement contains the identifier and no `cdhash`, and refuses to install otherwise. An ad-hoc signature would revoke Accessibility and Input Monitoring on every rebuild. It installs to one fixed path. Launch at login uses `SMAppService`.

## Synthesis decision

The arena ran two runners on the same brief, one on Opus and one on Sonnet, and a Sonnet judge scored them on a seven-point rubric. Both candidates converged on a desired-state reconciler, HID-layer key routing through carrier keys, run-loop global actors and a pure gesture machine, which is strong agreement on the core.

**Base: candidate B.** The judge and the parent agreed. B has one write entry per device with retry and backoff, a tap thread nothing else can stall, a tap pipeline with derived masks for v2, and it measured three facts that A left open.

**Grafts from A.**

- `ControlBehavior` per control, which ties firmware flags to host routing. It replaces B's fixed gesture and top-button fields, and it is the per-control shape that profiles need.
- The sans-I/O HID++ conversation and its firmware-model tests, generalized from `MXLink` to `HIDPPLink` for any HID++ device.
- The synthetic-event marker, so the tap never rewrites Hyperpoint's own events.

**Rebuilt for the user's later directives.** Both candidates hard-coded four devices. The judge scored B lower than A on absorbing open-ended devices. The rebuild replaces B's `KnownDevice` enum, `DeviceTable` and fixed `Intent` fields with profiles, `PresentDevice`, discovered capabilities, a carrier pool and per-sender tap rules. B's derived-schema codec stays, applied to a schema with a device list.

**Fixed from the judge's review.**

- B posted symbolic hotkeys from the HID thread without measuring it. `ActionPerformer` is on main, as in Mac Mouse Fix.
- A never opened the device. `HIDPPSession` opens its IOHIDDevice before registering the input report callback.
- B mirrored config in three places. `ConfigStore` is now the only owner.
- Both listed F18 to F20 in more than one table. The carrier pool is now the only list.

**Rejected.** A's single shared thread for the tap and HID++, because a slow `IOHIDDeviceSetReport` would delay every keystroke. B's `DeviceTable`, because it makes the device set closed.

## Tradeoffs accepted

- We accept rewriting every present device on every config save, in exchange for one apply path with no diffing.
- We accept a custom run-loop executor of about 40 lines, in exchange for compiler-checked thread confinement and synchronous C callbacks.
- We accept private API in three places (CGS symbolic hotkeys, `IOHIDEventGetSenderID`, and `CGEventSetHIDEvent` if v2 ever wants follow-the-finger swipes), in exchange for honouring the user's own Mission Control shortcuts and per-device pointer settings.
- We accept spawning `/usr/bin/hidutil` on device appearance and config change, in exchange for a documented interface instead of private SPI.
- We accept a read-only settings window while the file is invalid, in exchange for never overwriting a hand edit in progress.
- We accept that a crash leaves diverted buttons dead and Caps Lock as F18 until relaunch, in exchange for no helper process. Launch at login plus a relaunch converges everything.
- We accept that an older app cannot read a newer file, in exchange for unknown keys being errors.

## Alternatives considered

- **Per-device driver objects.** A `DeviceDriver` protocol with one class per device kind, each reading config and registering its own tap rules. Hyper spans keyboards and the 2.4G Return spans a mouse and the tap, so drivers would share the tap with no single owner, and config would be interpreted in several places. One compiler, `Intent.compile`, with per-device slots keeps the lifecycle per device and the interpretation in one place.
- **Event tap only, with attribution or seize.** Drop `hidutil` and remap every key in the tap. Keyboard sender ids are unverified, seizing from a non-root app is refused by TCC, and Escape to Right Option would need synthesized modifier state that breaks under secure input.
- **Async device actors.** Each device an `actor` with `apply() async`. Reentrancy at every `await` lets a config apply interleave with a connect apply, and timing tests need real clocks. CoreHID, which would make this cheap, delivered no input reports (measured).
- **A privileged helper over XPC.** Nothing here needs root, and it adds a second signed binary and a protocol to maintain.

## Open questions and risks

Each of these is settled by a prototype before the code that depends on it, not by asking.

1. **Hyper key against real apps.** The prototype proved the strategy with a Carbon hotkey, the mechanism global hotkey apps use. A check against the real Raycast hyper bindings comes when Hyperpoint first runs with the real Caps Lock to F18 mapping, which needs Karabiner quit.
2. **The 2.4G mouse's sender id.** The MX and the trackpad attribute correctly. The 2.4G mouse was not plugged in, so its pointer service is unmeasured.
3. **Device classification.** The MX reports keyboard as its primary usage, and the built-in keyboard also exposes a pointer. What decides whether a device appears as a mouse or a keyboard in the sidebar? The current proposal is pointer usage plus not built-in means mouse, with a per-profile override.
4. **The 2.4G dongle's services.** It is not plugged in, so its keyboard services and their ids are unmeasured.
5. **Thumb wheel invert while undiverted.** Solaar writes it, but firmware behavior on this mouse is inferred.
6. **Unprompted 0x1D4B over BLE.** If the MX does not send it after each reconnect, the connect callback and manual re-apply are the only triggers. A periodic read-back is the fallback.
7. **Click-through mechanics.** Making a background click act at once may need activating the window first and replaying the click. It needs a prototype in v2.
8. **Gesture distance.** 120 sensor counts is a guess. It is tuned by feel.
9. **Carrier collisions.** A keyboard with physical F13 to F24 keys would collide with the carrier pool. The pool could skip keys that a present keyboard reports.
10. **Smooth scrolling feel.** The defaults are a starting point for tuning by feel. Nobody measured them against BetterMouse. A free-spinning wheel may also send one tick backwards as it stops. That tick would end the glide and scroll back one boosted tick. Neither has been tried on the MX yet.

## Next implementation step

Build `ConfigCodec`, `Intent.compile`, `GestureMachine` and `HIDPPLink` against their tests. Then land the hyper key end to end first, because it needs no HID++ and exercises both threads, permissions and signing.

## Appendix A. Platform facts

Measured on this Mac or sourced from Solaar, logiops, Mac Mouse Fix, LinearMouse, Lazy Mouse and Apple TN2450, during the grounding run on 2026-10-23.

| Fact | Evidence |
| --- | --- |
| The MX Master 3 is one BLE IOHIDDevice with collections 1/6, 1/2, 1/1 and 0xFF43/0x0202. Only long reports (0x11, 20 bytes) exist, and device index 0xFF works. | measured |
| `IOHIDDeviceSetReport` works and replies arrive through the input report callback. Opening needs Input Monitoring. | measured, sourced |
| CoreHID matched the device but delivered no input reports in 10 s. | measured |
| On this mouse, 0x1B04 is at feature index 0x08, 0x2150 at 0x0E, 0x1D4B at 0x04. Indices are per device, so they are always discovered. | measured |
| Controls are 0x50, 0x51, 0x52, 0x53, 0x56, 0xC3, 0xC4, 0xD7. 0xC3 and 0xC4 are temporarily divertable and rawXY-capable. | measured |
| setCidReporting flags are 0x22 off, 0x23 divert, 0x33 divert plus rawXY. Divert is volatile. | sourced |
| BetterMouse currently diverts 0xC3, 0xC4 (flags 0x01) and the thumb wheel. | measured |
| macOS 27 ignores the CGEvent dock-swipe fields. Symbolic hotkeys 32, 33, 79, 81 trigger Mission Control, App Exposé and Space left and right. | sourced |
| `hidutil` mappings need no privileges and die with their service. `--matching` selects exactly one service each for the built-in and Magic keyboards. | sourced, measured |
| IOHIDManager ignores the `Built-In` matching key, and an unopened manager still delivers matching callbacks. | measured |
| Seizing a keyboard device is refused by TCC even for root. | sourced |
| Secure input disables keyboard event taps. | sourced |
| A listen-only event tap receives nothing without Input Monitoring. An active pass-through tap works with Accessibility alone. | measured |
| After a BLE reconnect the MX's `AppleUserHIDEventService` is published after its IOHIDDevice matches, so a walk down from the device at match time finds no event service. A first-match notification for `IOHIDEventService` reports it, and its registry ancestors include the IOHIDDevice's service. | measured |
| CG converts a one-line wheel event to 10 points. A pixel-unit scroll event is continuous, and setting one of its delta fields rewrites the others. | measured |
| AppKit reads a posted pixel scroll that carries a scroll phase as precise deltas, with `NSEvent` phases began, changed and ended. | measured |

## Appendix B. Prototype results

Both prototypes ran on 2026-10-23 in a throwaway probe app signed with the Apple Development identity, outside this repo. Neither changed a key mapping or a device setting.

**Hyper key.** A rewriting tap turned a posted F18 into hyper three ways, and a Carbon hotkey for ⌘⌃⌥⇧F16 checked whether an app sees it. Each strategy ran 8 times.

| Strategy | Hotkey fired | Modifier state still ⌘⌃⌥⇧ after release |
| --- | --- | --- |
| Overlay only. Drop F18, add ⌘⌃⌥⇧ to each key. | 8/8 | 8/8 |
| Post real modifier key events on the F18 edges. | 8/8, and 0/1 on its first run | 0/8 |
| Rewrite F18 in place into `flagsChanged`, plus the overlay. | 8/8 | 0/8 |

The third strategy wins. It posts nothing, so it has no ordering race with the events it rewrites, and the system's modifier state never stays stuck after release. With the overlay alone, the system would treat the next click as ⌘⌃⌥⇧-click until the next modifier key.

**Pointer sender id.** A pass-through tap at the HID level logged the sender id of every scroll, click and move for 90 seconds while the MX and the trackpad were used in turn.

| Device | Sender id | Which registry entry |
| --- | --- | --- |
| MX Master 3, wheel, clicks, movement | 0x100037032 | `AppleUserHIDEventService` of the MX |
| Built-in trackpad, scroll, clicks, movement | 0x100000d10 | `AppleMultitouchDevice` |

Every event carried a sender id, and all came from hardware (source pid 0).
