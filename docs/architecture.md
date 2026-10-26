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

`~/.config/hyperpoint/config.json` is the single source of truth. The settings window edits this file and nothing else. A fresh install writes it with `devices` and `ignored` empty. This is the owner's file after setting up their four devices from presets, which reproduces their BetterMouse and Karabiner setup.

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
        { "control": "thumbWheel", "when": "scroll", "do": "reverse" },
        { "control": { "button": 1 }, "when": "holdMove", "do": "scroll" }
      ],
      "gestures": { "fire": "pastDistance", "distance": 120 },
      "scrolling": {
        "smooth": {
          "duration": 4, "easeIn": 60, "brake": 2,
          "curve": [
            { "stepsPerSecond": 1, "pointsPerSecond": 40 },
            { "stepsPerSecond": 5, "pointsPerSecond": 250 },
            { "stepsPerSecond": 15, "pointsPerSecond": 900 },
            { "stepsPerSecond": 40, "pointsPerSecond": 2800 },
            { "stepsPerSecond": 120, "pointsPerSecond": 9000 }
          ]
        },
        "hiResWheel": true,
        "holdToScroll": { "speed": 1, "direction": "grab", "momentum": true },
        "clickThrough": { "left": true, "right": true }
      }
    },
    {
      "match": { "vendor": "0x1EA7", "product": "0x0002" },
      "name": "2.4G Mouse",
      "kind": "mouse",
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
- `kind` is `"mouse"` or `"keyboard"`. It puts the device in that list in the settings window, and only a keyboard can have the hyper key. Without it, the device's interfaces decide, which lists a mouse whose keys have an interface of their own, like the 2.4G mouse, as a keyboard. The 2.4G preset writes `"mouse"`, and the Devices tab changes it.
- A rule is `control`, `when`, `do`. Which `when` values a control accepts depends on its kind, and the parser rejects a rule that cannot work, with its path (for example `devices[1].rules[0].when`).
- A plain button is numbered as CGEvent numbers it. `{ "button": 1 }` is the right button, 2 the middle, 3 back and 4 forward. The left button, 0, cannot have rules.
- `"when": "holdMove"` with no direction is hold and move any way, and its only action is `"do": "scroll"`. A control with it may also have a click rule, but no hold-and-move swipes, because both would read the same movement.
- A key a mouse sends can be held as a modifier (`"when": "hold"`, `"do": { "modifier": … }`) or click a shortcut, not both. The modifier is mapped at the HID layer, so the key has no click left to give.
- A button held holds keys from its press to its release. `"when": "hold"` with `"do": { "modifier": "leftCommand" }` holds one modifier, and with `"do": { "shortcut": "ctrl+opt+space" }` holds the shortcut's modifiers and its key. The keys are down from the press, so the button has no click or hold-and-move rule beside it.
- An unknown key is an error with its path, so a typo cannot silently do nothing. An invalid file is rejected whole. The last good config keeps running, and the menu and settings window say what is wrong.
- `ignored` lists devices the user chose to ignore. A device with no profile and not ignored shows as new in the settings window and is left untouched. The Devices tab adds a new device to `ignored` and removes it again.
- A profile comes only from Set Up, which starts it from a preset, from a copy of another profile, or empty. The file never records which, so changing a preset later leaves every saved profile as it is.
- `"hyper": { "enabled": false }` turns the hyper key off on every keyboard. Each profile keeps its own `hyper`, so turning it back on restores them. A file without `enabled` has the hyper key on.
- Pause is runtime state, not config.

### Call site 1. The MX Master 3 connects

1. The IOHIDManager matching callback fires on the HID thread. `DeviceHub` groups the new IOHIDDevice interfaces into one `PresentDevice` and finds its profile by `match`.
2. The device has a HID++ collection, so its slot opens a `HIDPPSession`. Discovery reads the feature table and the control list (`getCount`, `getCidInfo`), which become the device's `Capabilities`.
3. `Intent.compile` turns the profile and the capabilities into a `DeviceSetup`. For the MX, that is `0xC3` as a gesture control that swipes (divert plus rawXY, flags `0x33`), `0xC4` as a press (divert only, flags `0x23`), and the thumb wheel undiverted and inverted. The right button cannot be diverted on this mouse, so its scroll rule goes to `TapRules` instead, keyed by the MX's event service.
4. The slot's worker writes all of it and reads it back. A timeout right after a BLE connect is normal, so `RetryPolicy` retries at 0.3, 1, 2, 4 and 8 seconds.
5. The journal logs the connect and the apply, and the menu shows "MX Master 3 reconnected at 15:06. Settings re-applied."

A 0x1D4B notification with the reconfigure flag, a config save, a permission grant, wake, resume and "Re-apply Settings Now" all enter at step 3 through the same call, `slot.invalidate(reason)`.

### Call site 2. The user sets up a new mouse

1. A connected device that no profile matches and `ignored` does not list goes into `EngineStatus.newDevices` with its match, name and kind. Hyperpoint writes nothing to it.
2. The Devices, Buttons and Scrolling tabs show its Set Up control. `SetupChoices` decides what it offers: the presets `DevicePreset.offered(for:kind:)` returns (one made for this exact model first, then any for its kind), then an empty profile for a mouse, then copies of saved profiles of the same kind. The first is the button and the rest are its menu.
3. The click sends `SettingsEdit.addDevice(match, name:, source)`, which `ConfigStore.update` applies to the file as it is on disk. It adds nothing when the device already has a profile or is ignored, when a model preset is for another device, or when the profile to copy is gone.
4. The reload enters call site 1 at step 3. The MX preset has HID++ rules, so the slot opens its session, discovers and writes. A HID++ mouse whose profile has none still opens its session to discover, read-only, so the Buttons tab offers its real controls. Its plan is nil, so the link sends get requests only and writes nothing until a rule needs it. A Logitech keyboard without HID++ rules is never opened.

### Call site 3. Caps Lock is held and R is pressed

1. When a keyboard whose profile has `"hyper": true` appears, its slot sets `UserKeyMapping` on that keyboard's service only. Caps Lock (usage 0x39) becomes F18 (0x6D). The OS never sees Caps Lock, so there is no LED toggle and no caps delay.
2. F18 key-down reaches the event tap on the tap thread. `CarrierStage` finds F18 in `TapRules.carriers` as `.holdModifiers(⌘⌃⌥⇧)` and rewrites the event in place into a `flagsChanged` event with ⌘⌃⌥⇧ set. The system's modifier state now shows hyper held.
3. R key-down gets ⌘⌃⌥⇧ added to its flags.
4. F18 key-up is rewritten in place into a `flagsChanged` event with the four modifiers cleared, so the system's modifier state goes back to normal. A tap timeout or a keyboard disappearing also clears the hyper state, so hyper can never stay stuck on.

The hyper prototype chose this strategy ([Appendix B](#appendix-b-prototype-results)).

The 2.4G mouse uses the same mechanism. Its keyboard interface gets `UserKeyMapping` the same way. Escape maps straight to Right Option (0xE6) at the HID layer, a `.native` route, so holding it is a real held modifier and it works in password fields. Return maps to F13, a carrier whose meaning is `.press(⌥⇧S)`. The tap drops F13's key-down and has `ActionPerformer` post ⌥⇧S, and it drops the key's repeats and its key-up too. Without the Accessibility grant there is no tap, so Return is left as Return while Escape still becomes Right Option.

### Call site 4. Back is held as ⌘ and the left button clicks

The MX profile has `{ "control": { "hidpp": "0x53" }, "when": "hold", "do": { "modifier": "leftCommand" } }`.

1. `Intent.compile` gives 0x53 `ControlBehavior.hold(KeyHold)`, which diverts it without raw movement (flags `0x23`), so the pointer moves as usual while it is held.
2. The press arrives as a 0x1B04 notification on the HID thread. `HIDPPLink` emits `holdKeys(0x53, ⌘)`, and the slot sends `KeyHoldEvent.press(.control(device, 0x53), ⌘)` on its ordered stream to the tap thread.
3. `TapHost` hands it to `HeldKeys`, which returns a marked `flagsChanged` event for Left Command, and turns on the overlay tap before it posts the event at the HID tap. Apps see ⌘ go down as a keyboard's would.
4. The posted change alone does not keep ⌘ held. The next hardware event, here the hand moving the mouse, puts the real modifier state back within about 20 ms (measured). So while modifiers are held, the overlay tap adds them to every other click, drag, move, scroll and key on its way through the HID tap, and the left click reaches apps as a ⌘-click. The overlay is newer than the main tap, so it runs first and smooth scrolling passes a ⌘-scroll, and it is on only while modifiers are held, so normal use never pays for it.
5. The release sends `releaseKeys`. `TapHost` turns the overlay off first, then posts the `flagsChanged` event that lets go of ⌘. A release that never comes is covered by an apply, the device going away, a tap timeout, pause and quit, which all let go.

`OverlaySwitch` calls macOS only when the overlay's state changes. Turning a tap off sends it a notice that it was turned off, and answering that notice with another call made the two chase each other: the tap thread spun on them, and every key and click waited seconds for it (measured). Only a timeout turns it back on, while modifiers are held.

A plain button does the same in `ButtonStage`. Its press becomes `TapVerdict.keys(.press)`, its drags reach apps as plain `mouseMoved` events because apps never saw the press, and its release becomes `.keys(.release)`. A shortcut holds its modifiers in the order macOS menus show them, then its key, and lets go in reverse. The keys are posted, not mapped at the HID layer as a mouse's Escape is, because a button press is a HID++ notification or a mouse event, which no key map can reach.

### Call site 5. The user adds a rule by pressing a button

1. Add Rule on the Buttons tab calls `engine.listen(for: match)`. The engine's `Listener` arms one listen with a new id and a 10 s timeout. It refuses at once, with the reason in `DeviceStatus.listen`, while paused, when the mouse is not connected, or when neither the tap nor HID++ can hear it.
2. Listening is an input to `Intent.compile`, as a `ListenTarget`. For that device only, the HID++ plan becomes `HIDPPSetup.listening`, which diverts every divertable control but the left button without raw movement. On a mouse with a thumb wheel it also diverts the wheel and keeps its direction, so a turn stops scrolling and reaches `HIDPPLink` as a 0x2150 notification, which it reports as `HIDPPEvent.heard(.thumbWheel)` on the same path as a press. Its key map is cleared, so its keys reach the tap as themselves, and `TapRules.listen` names its event services. A listen alone installs the tap. Paused and quitting still compile to neutral. The engine then calls `slot.invalidate(.listen)` on that device, so a listen is one more absolute write.
3. The first press comes in through whichever route sees it. `HIDPPLink` reports a listened control as `HIDPPEvent.heard` and runs no gesture or action. In the tap, `LearnStage` runs before every other stage. It takes the first right or other button press, or key press, from the device's senders and reports it as `TapSignal.heard`. It then keeps that press's drags, repeats and release from apps and rules, also after new rules arrive. When the listen was the tap's only reason to run, the tap is removed once the press is heard, and the release reaches apps. The left button is not among its events.
4. The engine matches the press to the armed listen by its id or its device, so a late report changes nothing. `ListenPlan.heard` names the press as a `Control`, and a carrier key pressed before the clear landed is named as the key that sent it. The `LearnedPress` goes to the window once, in order, on `engine.heard`. The listen goes back to idle, the intent loses the overlay, and the same invalidate writes the real setup back.
5. `SettingsModel.learned` turns the press into config through `RuleChoices.learned`. A plain button whose HID++ control the mouse can divert becomes that control. The rule takes the control's first free trigger and that trigger's first action, and reaches the file as `SettingsEdit.addRule`. A control with every trigger taken adds nothing. Add Rule's menu sends a picked control through the same function, for a mouse that is not connected. A rule's Button cell listens the same way, and `SettingsModel` remembers the listen is for that rule's `RuleKey`, so `RuleChoices.learned(_:replacing:)` moves the rule to the pressed control as one `SettingsEdit.replaceRule`, or changes nothing when the press is the rule's own button.

Every other exit is a transition on the same `Listener`. Cancel, Esc, a tab or mouse switch and closing the window end the listen silently. The timeout, a disconnect, pause, wake and losing every route end it with a reason the window shows. A config save keeps it and compiles the overlay over the new profile, unless the profile is gone. Quit ends it before writing neutral.

A read-only HID++ profile writes nothing at launch, so a crash mid-listen would keep the listen's divert. `DivertLatch` records the match in `UserDefaults` before the first write. A slot for a latched mouse starts as if it had already written, so it writes native once. A clean quit clears the latch.

## Shape

### Base and grafts

This design is candidate B of a two-model architect arena, with grafts from candidate A, rebuilt for open-ended devices. [Synthesis decision](#synthesis-decision) records what came from where.

### Data structures

| Type | What it encodes |
| --- | --- |
| `Config` | The parsed file. `ConfigCodec.decode` is the only way in. The unknown-key check walks the user's JSON against the encoded types, so no key list exists to drift. |
| `DeviceProfile` | One device entry. `match`, `name`, `kind`, `rules: [Rule]`, `gestures`, `scrolling`, `hyper`. |
| `DevicePreset` | The closed list of starting profiles: one per measured model (the MX Master 3 and the 2.4G mouse) and one for any keyboard. `offered(for:kind:)` ranks them for a new device, its own model first. Set Up copies one into the file once. |
| `DeviceMatch` | Vendor and product, or `builtIn`. One value classifies a `PresentDevice` and renders hidutil `--matching`. IOHIDManager ignores `Built-In` (measured), so Swift's `matches` is the authority and the manager is only a prefilter. |
| `Rule` | `Control`, `Trigger`, `Action`. |
| `Control` | `.hidpp(CID)`, `.thumbWheel`, `.key(HIDUsage)` for a key a mouse sends from a keyboard interface, `.button(Int)` for a plain mouse button in CGEvent numbering. |
| `Trigger` | `.click`, `.hold`, `.holdMove(Direction?)`, `.scroll`. A nil direction is hold and move any way. |
| `Action` | `.system(SystemAction)`, `.shortcut(Chord)`, `.modifier(HeldModifier)`, `.reverse`, `.scroll`. `SystemAction.rawValue` is the CGS symbolic hotkey id (32, 33, 79, 81), so the id table is the enum. On a hold, `.modifier` and `.shortcut` stay down until the release. |
| `PresentDevice` | A connected device, grouped from its IOHIDDevice interfaces. Instance id, `DeviceKey`, name, transport, the ids of its HID event services, `Capabilities`. |
| `DeviceRoster` | The registry ids of each present device's IOHIDDevice interfaces and HID event services. `DeviceHub` feeds it keyboard, mouse and HID++ interfaces from IOKit, and it decides which device a newly published event service belongs to. It never tracks a trackpad, and a device with a keyboard interface is described by that interface whichever interface enumerates first. |
| `Capabilities` | What discovery found. HID++ controls with their flags (temporary divert, rawXY), thumb wheel, keyboard interface, pointer, keyboard. Never stored in config. |
| `Intent` | `Intent.compile(config, paused, tapAvailable, present, listening)`. A pure function that returns a `DeviceSetup` per present device and one `TapRules`, with the listened device's overlay and its `ListenPlan`. Paused compiles to `Intent.neutral`, so pause is the same reconcile as a config change. |
| `DeviceSetup` | What lives on the device or its service. `hidpp: [CID: ControlBehavior]`, `thumbWheelInverted`, `keyMap: [KeyRoute]`. Written whole on every apply. |
| `ControlBehavior` | `.native`, `.press(Action)`, `.gesture(GesturePlan)`, `.hold(KeyHold)`. The firmware flags (`0x22`, `0x23`, `0x33`) and the host routing derive from the same case, so "diverted with rawXY but not fed to the recognizer" cannot be built. HID++ controls and plain buttons build it from their rules with one initializer. |
| `KeyHold` | The keys a held button holds: modifiers in the order they go down, then at most one other key. A shortcut's modifiers are the left keys. |
| `HeldKeys` | Every hold in progress, by `KeyHolder` (a plain button, or one device's HID++ control), and the marked key events that press and release them. A modifier two holds share goes up with the last. Its `flags` are what the overlay tap adds to every other event while modifiers are held. |
| `OverlaySwitch` | Whether the overlay tap is on, so only a change of state calls macOS. |
| `GesturePlan` | The distance, the click action, and `GestureMoves`, which is `.swipes([Direction: Action], fire)` or `.scroll(HoldScrollPlan)`. One control cannot do both. |
| `HoldScrollPlan` | Page points per unit of the control's movement, signed for the direction, and the release glide, or nil without momentum. |
| `HoldScrollEvent` | `.began(plan)`, `.moved(dx, dy)` in page points, `.ended`. What both recognizers send `HoldScrollAnimator`. |
| `KeyRoute` | One remap, from a source usage to `.native(usage)` or `.carrier(Carrier, CarrierMeaning)`. The hidutil JSON and the tap's carrier rules both derive from the same `[KeyRoute]`. |
| `Carrier` | A reserved F13 to F20 key. Hyper is F18. Each shortcut that a key rule clicks gets one carrier from the rest of the pool, in file order, so a device that connects or leaves never moves another device's carrier. A rule past the seventh shortcut is skipped. The pool is the only place these numbers exist, as a HID usage and a virtual key code side by side. |
| `TapRules` | Carrier meanings, plus per-sender smooth scrolling and per-sender plain-button behaviors (`[ButtonKey: ControlBehavior]`, a sender id and a button number), keyed by the HID service ids of the devices whose profiles enable them. While a listen is armed, its id and the listened device's senders. |
| `Listener` | The engine's one listen, which is idle, armed with an id, a device and a deadline, or ended with its reason. Every exit is a transition, and a report for a listen that already ended names nothing armed. |
| `ListenPlan` | The compiled side of a listen. It names a press as a `Control`, through the carrier routes the listen cleared for a key pressed before the clear landed. |
| `EngineStatus` | One immutable value the UI renders. Run state, permissions, tap state, per-device link, last apply and capabilities, hyper and listen status, new devices, last reconnect. |

The dominant access patterns, traced through these types:

- **A HID++ notification** resolves to its slot in O(1) by device instance. `HIDPPLink` decodes it through the session's feature map and feeds the gesture machine. No allocation and no thread hop.
- **A tap event** costs one carrier lookup by key code. Scroll events and right and other button presses also cost one lookup by sender id. Drags and releases cost none, because they only match the one button the stage holds. A sender with no entry passes untouched, so the trackpad is never smoothed. While a listen is armed, a button or key press also costs one sender read.
- **A config save** recompiles the intent once and invalidates every present slot. Each slot writes its whole setup. There is no diffing logic to get wrong.

### Module map

One SwiftPM library with three folders and a thin app target, built into a signed `.app` by a script.

| Path | Access | Holds |
| --- | --- | --- |
| `Sources/HyperpointKit/Model` | public | `Config` and its parts, `DevicePreset`, `ConfigCodec`, `EngineStatus` |
| `Sources/HyperpointKit/Core` | internal, pure | `Intent`, `KeyRoute`, `Carrier`, HID++ codec, `HIDPPLink`, `GestureMachine`, `TapPipeline` and its stages, `HeldKeys`, `ScrollAnimator`, `DeviceRoster`, `ApplyScheduler`, `RetryPolicy`, `Capabilities`, `Listener` |
| `Sources/HyperpointKit/Runtime` | internal, except `Engine`, `ConfigStore`, `Permissions` | executors, `DeviceHub`, `Slot`, `HIDPPSession`, `KeyMapWriter`, `TapHost`, `ActionPerformer`, `Journal`, `DivertLatch` |
| `Sources/Hyperpoint` | app | `AppModel`, the menu, Welcome and settings views |

Per-layer SwiftPM targets do not stop the app importing a lower layer (measured), but access control does hide internals across the library boundary (measured). `scripts/check-layers.sh` fails the build when Core imports IOKit or anything from Runtime.

### Threading model

Each device-facing thread is a global actor whose executor is that thread's CFRunLoop. Actor isolation is then thread confinement, which the compiler checks. A C callback that fires on the run loop enters the actor synchronously with `assumeIsolated`, with no hop and no copy. Both candidates spiked this pattern on this Mac. Every C callback is a file-scope `nonisolated` function, because a closure written inside main-actor code traps on another thread (measured).

| Context | Owns |
| --- | --- |
| Main actor | `AppModel`, SwiftUI, `ActionPerformer` (symbolic hotkey lookup runs on main in Mac Mouse Fix, so Hyperpoint does the same) |
| `@HIDActor` | `Engine` (desired state), `DeviceHub` and its IOHIDManager, every `Slot`, every `HIDPPSession` and its `HIDPPLink`, `Journal` |
| `@TapActor` | `TapHost`, the mach port, `TapPipeline`, the `ScrollAnimator` and `HoldScrollAnimator` instances and their display link, the pointer freeze, `HeldKeys` and the overlay tap, the watchdog. Nothing else ever runs here. |
| Cooperative pool | `ConfigStore` (an actor that owns the file), `KeyMapWriter` (the `hidutil` process), permission polling |

State crosses only as immutable `Sendable` values.

| From, to | Carrier | Policy |
| --- | --- | --- |
| Main to HID | `await engine.reapplyAll()`, `setPaused`, `listen`, `stopListening` | one hop per user action |
| HID to main | `engine.statuses` | latest wins |
| HID to main | `engine.actions` | ordered, for `ActionPerformer` |
| HID to main | `engine.heard` | ordered, each heard press once, for the settings window |
| ConfigStore to HID and main | `store.events()` | each element is a full state |
| HID to tap | `TapRules` | latest wins, applied between events |
| HID to tap | `HoldScrollEvent` from a HID++ control | ordered, every event, because a lost end would leave the pointer frozen |
| HID to tap | `KeyHoldEvent` from a HID++ control | ordered, every event, because a lost release would leave a key held |
| Tap to HID | `TapSignal` (installed, install failed, removed, re-enabled, heard) | ordered, rare |
| Tap to main | plain-button actions, into `engine.actions` | ordered |

There is no lock and no shared mutable object. Config has one owner, `ConfigStore`. The engine and the UI each hold a copy of the latest value it published, and neither writes it back except through `ConfigStore.update`.

### Load-bearing decisions

1. **One reconcile path.** Every trigger calls `slot.invalidate(reason)`. `ApplyScheduler` gives each device one writer and collapses triggers that arrive mid-apply into one follow-up. Every write is absolute, so running an apply twice, or after a crash halfway, ends in the same state (per make-operations-idempotent).
2. **The HID++ conversation is a value.** `HIDPPLink` takes bytes and time and returns bytes, events and a deadline. Discovery, writes, read-back, retries, notifications, button edges and gesture recognition are all transitions on it. Tests drive it against a firmware model seeded with the measured BetterMouse state, and they assert the model's end state, not the request order (per test-behavior-not-implementation).
3. **Device identity is decided at the HID layer for keys.** `hidutil` maps keys per service, and the tap only sees carrier key codes. The tap never has to work out which keyboard sent a key. No device is seized.
4. **Pointer events are attributed by sender id.** Per-device scrolling, click-through and plain-button rules need to know which mouse sent a scroll or click. The tap reads the sender id with `CGEventCopyIOHIDEvent` and `IOHIDEventGetSenderID`, as LinearMouse does, and looks it up in `TapRules`. This is private API. The prototype measured it on this Mac. The sender id is the registry id of the device's HID event service (for the MX, `AppleUserHIDEventService`), not of its `IOHIDDevice`, so `DeviceHub` records the event service ids under each `PresentDevice`. Over BLE the event service is published after the IOHIDDevice matches (measured on an MX reconnect), so `DeviceHub` also watches for new `IOHIDEventService` entries. `DeviceRoster` gives each one to the device that owns one of its registry ancestors, and the engine recompiles `TapRules`.
5. **Profiles are data, presets start them, capabilities are discovered.** The file holds every setting of every device. A preset is code that writes a whole profile once, on Set Up, and nothing in the file refers back to it. So a fresh install starts with no devices, and a preset change never moves a saved device. A HID++ device's controls come from `getCidInfo`, so a different Logitech mouse works without code changes.

### Invariants and boundaries

- `KeyCode`, `HIDUsage`, `CID` and `SenderID` are distinct types (per type-system-discipline).
- HID++ wire types stay internal to Core. The runtime sees report bytes in and out, nothing else.
- Validation happens at five boundaries and nowhere else (per boundary-discipline). `ConfigCodec` for the file, the HID++ codec for device bytes, `KeyMapWriter` for `hidutil` output, `DeviceHub` for IOKit properties, and `TapHost` for CGEvents.
- `TapPipeline.reset()` runs on tap timeout, on every keyboard removal and before new rules replace the pipeline, so a lost key-up cannot leave hyper held. It also returns a plain-button press the stage was holding back, which `TapHost` posts so that the button's real release pairs with it, and says whether a scroll ended. The press a listen took stays taken through a reset and new rules, so its release is kept from apps too. A new press of the same button or key means that release was lost.
- Keys a button holds go up on its release, on any pipeline reset, on tap timeout, on uninstall (pause, quit, a lost permission), on an apply to its HID++ device and when that device goes away. `TapHost` posts every key event a hold makes, so the downs and ups of one key never cross threads.
- The pointer is frozen only while a hold scrolls, and for a plain button from its press. `TapHost` frees it on the release, on the scroll's end, on any pipeline reset, on tap timeout, on uninstall (pause, quit, a lost permission) and when no display can run frames. `Engine.shutdown` waits for the uninstall, so quitting mid-scroll frees it.
- Every event Hyperpoint posts carries a marker in `eventSourceUserData`, and every stage passes marked events untouched. Hyperpoint's own ⇧⌘4, smooth-scroll, hold-scroll and replayed clicks are never rewritten.

### Gesture machine

`GestureMachine` is a pure machine with no clock. Inputs are `press(GesturePlan)`, `move(dx, dy)`, `release` and `cancel`, with movement in the control's own unit, sensor counts for HID++ raw movement and points for pointer drags. States are `idle`, `tracking(plan, dx, dy)`, `consumed` and `scrolling(plan)`. Outputs are `click(Action?)`, `perform(Action)` and `scroll(HoldScrollEvent)`. The plan is captured at press, so a config edit mid-gesture cannot change a gesture in flight.

- In `pastDistance` mode, the move that makes net travel reach `distance` fires the swipe for the dominant axis. In `onRelease` mode, the release decides. Below `distance`, the release is a click.
- A swipe in a direction with no rule is consumed. It fires nothing and is not a click.
- With a scroll plan, the move that makes net travel reach `distance` emits `began`, each later move `moved` scaled by the plan's gain, and the release `ended`. It is never a click once it scrolls.
- A press while tracking means a release was lost, so the machine starts over, ending a scroll first. Device removal and every apply send `cancel`, which also ends a scroll.

### v2 scrolling and clicks

The tap-side ones live in `TapPipeline` as stages, each with `static let interests`. `TapPipeline.mask` is derived from the stages, never hand-listed. Their settings reach the tap as per-sender entries in `TapRules`.

- **Smooth scrolling.** `ScrollStage` drops wheel steps from enabled senders and feeds `ScrollAnimator`, a pure model of one velocity pulse per step, driven by the display link of the screen under the pointer. It posts marked continuous scroll events. [Smooth scrolling](#smooth-scrolling) has the model.
- **High-resolution wheel.** HID++ feature 0x2121 adds one write and one read-back to the device setup. `ScrollStage` then treats the finer deltas as input.
- **Hold to scroll.** Any button with a hold and move → scroll rule. A HID++ control recognizes it in `HIDPPLink` from raw movement, and a plain button in `ButtonStage` from drags. [Hold to scroll](#hold-to-scroll) has the model.
- **Click-through.** `ClickThroughStage` sees a click from an enabled sender on a background window and makes it act at once. How it activates the window without eating the click is open ([Open questions](#open-questions-and-risks)).

### Smooth scrolling

The MX wheel without BetterMouse sends line-based wheel events, and apps such as Telegram animate each one as a separate jump. Hyperpoint replaces those events with a glide of continuous pixel scrolls, the kind a trackpad sends.

`ScrollStage` takes a wheel event when it is line-based, vertical, has no modifier held, and comes from a sender in `TapRules.smoothScroll`. Every other scroll passes untouched. Trackpad scrolls are continuous, the thumb wheel is horizontal, shift-scroll and zoom carry a modifier, and other mice have no entry. macOS has already accelerated the event's line delta (up to 13 lines for one detent, measured), so `ScrollStage` ignores it. It counts the wheel's own detents from the event's IOHIDEvent (`IOHIDEventGetFloatValue`, field `0x60001`) instead, 1 to 3 per event in a free spin, and counts 1 when there is none.

The speed comes from `curve`, a list of points that map the spin rate, in steps per second, to a scroll speed, in points per second. Points join with straight lines on log-log axes, so a fixed distance per step is a straight line and stays exact between points. Beyond the last point the speed stays flat. One step goes `curve(r) / r` points, where `r` is the spin rate. `SpinRate` estimates it from the intervals between steps, moving halfway to each new interval. A step after a pause longer than one step at the curve's first rate counts as that rate, so a single step goes `curve(r₀) / r₀`. With the default curve that is 40 points, a native notch is 10, and a step goes 50 points at 5 steps per second, 60 at 15 and 75 at 120.

`ScrollAnimator` turns each step into a pulse of velocity. The pulse rises from rest along smoothstep over `easeIn`, so the page never jumps from rest, then falls as `(1 - t / duration) ^ brake`. Pulses add up. A step travels exactly its distance, and a steady spin at rate `r` scrolls at `curve(r)` whatever `duration`, `brake` and `easeIn` are, so those three shape only the glide. A step the other way ends the gesture on the next frame and starts a new one.

AppKit takes the precise delta of a posted scroll from its integer point field alone (measured, see Appendix A), so the frames post whole points. `WholePoints` rounds the running total, which keeps the page within half a point of the exact glide, and a steady 2.7 points a frame posts 3, 3, 2, never 4 next to 2. The fixed-point field carries the exact value, for apps that read `deltaY`. A glide slowing through a few points a second would still move by single points at growing intervals. So once its steps have eased in, a glide never moves slower than 60 points a second. It finishes at that speed, a point every other frame at 120 Hz, and stops.

| Key | Meaning | Default | Range |
| --- | --- | --- | --- |
| `duration` | How long a step's glide lasts after it reaches full speed, in tenths of a second | 4 | 1 to 20 |
| `brake` | Exponent of the velocity decay. At 1 the glide slows evenly. Higher values brake hard first and coast into a soft stop. | 2 | 0.5 to 10 |
| `easeIn` | Milliseconds a step takes to reach full speed. The distance stays the same. 0 starts it at full speed. | 60 | 0 to 300 |
| `curve` | `[{ "stepsPerSecond", "pointsPerSecond" }]`, at least two points, rates rising, speeds never falling | (1, 40), (5, 250), (15, 900), (40, 2800), (120, 9000) | rates 1 to 150, speeds 10 to 30,000 |

`duration` is in tenths of a second so that BetterMouse's value of 4, whose unit is unknown, starts as a 0.4 s glide. A file without `easeIn` gets 60, and one without `curve` gets the default curve. A file written before the curve, with `speed`, `startBoost` and `acceleration`, still parses. Each step there went `speed × boost × gain`, so the parser samples that at 1, 5, 15, 40 and 150 steps per second and where the boost and gain bend, and the next save writes `curve` alone. A fixed distance per step converts exactly. The old default with acceleration on converts within 6.3%, at 8.6 steps per second.

The settings window's Scrolling tab draws `curve` as a graph on the same log-log axes, so the drawn line is exactly what the wheel does. Shaded bands mark the MX wheel's measured rates: slow 4 to 12, medium 15 to 17, fast about 36 and a flick about 120 events per second. A point drags between its neighbours, double-clicking the line adds a point on it, and double-clicking a point removes it, from 2 to 10 points. The readout gives the speed and the distance per step under the pointer, and a drag saves once, on mouse-up.

`TapHost` drives the frames from a display link, `NSScreen.displayLink(target:selector:)`, added to the tap thread's run loop, so each frame lands at the same point of the refresh and the animator gets the frame's `targetTimestamp`, on the same clock as the steps. The link follows the display under the pointer, because the external monitor here runs at 60 Hz and the built-in one at 120 Hz. It runs only while a glide does, and pauses when the animator is idle. A glide that sees no frame for 0.1 s rebuilds the link, in case its display went away. Each frame is a new `CGEvent` in pixel units, posted at the session level with the scroll phase began, changed or ended and the synthetic marker. AppKit reads these as precise deltas with matching phases (measured). A config save sends new `TapRules`, so changed settings apply from the next step.

### Hold to scroll

The user asked to generalize right-button pan into an action any button can have. So it is one action, `"do": "scroll"`, on the non-directional trigger `"when": "holdMove"`, and the right-button pan of the earlier design is that rule on button 1. The MX Master 3 preset gives it to the right button only, because holding the top button to scroll felt wrong in the user's live test. A file that still has `scrolling.rightButtonPan` decodes to the rule plus `holdToScroll` with its momentum, and the next save writes the new form.

A press does nothing yet. A release before the movement passes the profile's `gestures.distance` is the click. That is the control's click rule, or for a plain button with none, the original click replayed. Movement past the distance starts scrolling. From then on each movement scrolls the page by movement × speed on both axes, and the pointer stays where it is. On release the page keeps the hand's speed and glides to a stop if `momentum` is on.

Two recognizers feed one animator.

- **HID++ controls** whose capabilities say rawXY. The rule diverts the control with raw movement (`0x33`), and `GestureMachine` in `HIDPPLink` does the rest from `divertedRawXY` notifications on the HID thread. Its scroll events cross to the tap thread on their own ordered stream. The HID thread never posts a scroll.
- **Plain buttons**, right and other mouse events from a sender with rules. `ButtonStage` holds back the press, keeps a marked copy and feeds drag deltas to its own `GestureMachine`. A short press posts the copy and a marked copy of the release at the press location, in order, at the HID tap. A scroll drops every drag, so apps never see one. The left button is never watched.

`HoldScrollAnimator` on the tap thread posts what a trackpad posts. While the hand moves, each display frame carries the movement since the last frame as one continuous pixel scroll on both axes, with scroll phase began, then changed, then ended. After release it posts momentum frames, momentum phase begin, continue and end, with no scroll phase. Frames post whole points, as the wheel's glide does, rounded on the running total per axis. The display link pauses while the hand holds still.

The release speed is the hand's movement over its last few tens of milliseconds. Movement and the time it took are each weighted by `exp(-age / 0.04 s)`, and the speed is their ratio. That ratio is exact for a steady hand however often the device reports, and a hand that stopped before letting go has nearly none. A release slower than 150 points a second does not glide. The glide is the wheel step's glide with no ease-in, decaying as `(1 - t / duration) ^ brake` with the profile's smooth-scrolling `duration` and `brake`, or their defaults when smooth scrolling is off. It starts at the release speed and travels speed × duration / (brake + 1). A new hold during a glide ends it first.

`TapHost` freezes the pointer with `CGAssociateMouseAndMouseCursorPosition(false)` and frees it when the hold ends, so the freeze does not depend on whether raw-movement divert or dropped drags stop the pointer by themselves. A plain button freezes it from the press, while its drags still count toward the distance. No drag before the distance moves the pointer, so a fast flick cannot carry it off before the scroll starts. An HID++ control freezes it when its scroll begins.

**Units.** Raw movement is in sensor counts, and drags are in points macOS has already accelerated. At speed 1 the page should move as far as the pointer would have, so a drag scrolls its own points, and a count is worth `HoldScrollPlan.pointsPerCount` points, measured (Appendix A). The gesture distance stays in sensor counts in the file, so a plain button's threshold is `distance × pointsPerCount` points, the same hand travel for both.

| Key | Meaning | Default | Range |
| --- | --- | --- | --- |
| `speed` | Page movement per hand movement. At 1 the page follows the hand. | 1 | 0.25 to 4 |
| `direction` | `grab` moves the page with the hand, like a trackpad. `wheel` scrolls down when the hand moves down, like the wheel. | `grab` | |
| `momentum` | Glide on after a release while moving | true | |

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
- We accept that a crash leaves diverted buttons dead and Caps Lock as F18 until relaunch, in exchange for no helper process. Launch at login plus a relaunch converges everything. A relaunch knows a key map is Hyperpoint's by its carriers, so a map with only modifier routes, such as Escape → Right Option alone, stays until the device reconnects if its rule is removed before the relaunch. A crash while a button holds keys leaves them down until that key is pressed and released.
- We accept that an older app cannot read a newer file, in exchange for unknown keys being errors.

## Alternatives considered

- **Per-device driver objects.** A `DeviceDriver` protocol with one class per device kind, each reading config and registering its own tap rules. Hyper spans keyboards and the 2.4G Return spans a mouse and the tap, so drivers would share the tap with no single owner, and config would be interpreted in several places. One compiler, `Intent.compile`, with per-device slots keeps the lifecycle per device and the interpretation in one place.
- **Event tap only, with attribution or seize.** Drop `hidutil` and remap every key in the tap. Keyboard sender ids are unverified, seizing from a non-root app is refused by TCC, and Escape to Right Option would need synthesized modifier state that breaks under secure input.
- **Async device actors.** Each device an `actor` with `apply() async`. Reentrancy at every `await` lets a config apply interleave with a connect apply, and timing tests need real clocks. CoreHID, which would make this cheap, delivered no input reports (measured).
- **A privileged helper over XPC.** Nothing here needs root, and it adds a second signed binary and a protocol to maintain.

## Open questions and risks

Each of these is settled by a prototype before the code that depends on it, not by asking.

1. **Hyper key against real apps.** The prototype proved the strategy with a Carbon hotkey, the mechanism global hotkey apps use. A check against the real Raycast hyper bindings comes when Hyperpoint first runs with the real Caps Lock to F18 mapping, which needs Karabiner quit.
2. **The 2.4G mouse's sender id.** The MX and the trackpad attribute correctly. The 2.4G mouse's pointer interface owns event service 0x10005214e, which `DeviceHub` now records, but no pointer event has been logged with that sender id yet.
3. **Device classification.** The MX reports keyboard as its primary usage, and the built-in keyboard also exposes a pointer. What decides whether a device appears as a mouse or a keyboard in the settings window? Today a device with a keyboard interface takes its kind from that interface (a keyboard unless the interface also has a pointer collection or the device is built in), and any other device is a mouse. Trackpads, the built-in one included, are not listed. So the 2.4G mouse, whose keys come from an interface of their own (measured), shows as a keyboard. Its pointer interface looks like a keyboard's mouse-keys interface, so the structure cannot tell them apart. A profile's `kind` overrides this, and the 2.4G preset sets it to mouse.
4. **The 2.4G dongle's services.** Measured on 2026-10-25, see Appendix A. Its keys and its pointer are separate interfaces, each with one event service.
5. **Thumb wheel invert while undiverted.** Solaar writes it, but firmware behavior on this mouse is inferred.
6. **Unprompted 0x1D4B over BLE.** If the MX does not send it after each reconnect, the connect callback and manual re-apply are the only triggers. A periodic read-back is the fallback.
7. **Hold-to-scroll feel and the frozen pointer under raw-movement divert.** Whether the MX keeps moving the pointer while a rawXY-diverted control is held is unmeasured, and the freeze makes it moot. Whether `CGAssociateMouseAndMouseCursorPosition` holds from a background agent app, and whether the glide's length and the 150 pt/s threshold feel right, are for the user's journey.
8. **Click-through mechanics.** Making a background click act at once may need activating the window first and replaying the click. It needs a prototype in v2.
9. **Gesture distance.** 120 sensor counts is a guess. It is tuned by feel.
10. **Carrier collisions.** A keyboard with physical F13 to F20 keys would collide with the carrier pool. The pool could skip keys that a present keyboard reports.
11. **Smooth scrolling feel.** The default curve comes from the MX wheel's measured rates, and the glide's defaults are a starting point for tuning by feel. A free-spinning wheel may also send one step backwards as it stops. That step would end the glide and scroll back one step.
12. **Listening through the tap.** Whether the 2.4G mouse's keys carry its keyboard service's sender id at the tap, and whether a diverted control held while a listen's restore write lands sends a native release, are unmeasured. The listening journey in the verify skill's settings window feature settles both.
13. **Plain buttons other than the right one.** macOS attaches no IOHIDEvent to an other-button press: the MX's Back arrived at the tap with sender 0 while its left clicks carried its event service (measured). So `ButtonStage` cannot tell which mouse sent a middle, back or forward press, and plain-button rules on buttons 2 to 4 do not fire. The MX's own buttons are unaffected, because the pickers name them as HID++ controls. Attributing them needs another source, such as the last pointer event that carried a sender.

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
| Controls are 0x50, 0x51, 0x52, 0x53, 0x56, 0xC3, 0xC4, 0xD7. 0xC3 and 0xC4 are temporarily divertable and rawXY-capable. 0xD7 is flagged virtual (getCidInfo flags 0xA0, group 4, no group mask): it has no physical button, so discovery leaves it out. The wheel click is 0x52. | measured |
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
| `NSEvent.scrollingDeltaY` of a posted pixel scroll is its integer point delta (field 96). Setting each field from 0 to 1023 in turn to 2.7 changed it only through field 96 (truncated) and the line delta. The fixed-point delta (field 93) keeps its fraction but reaches only `deltaY`. A float scroll IOHIDEvent attached with `SLEventSetIOHIDEvent` survives delivery through the window server and is ignored. | measured |
| `NSScreen.displayLink(target:selector:)` added to a background thread's run loop fires on that thread at the screen's refresh, 16.67 ms on the external monitor and 8.33 ms on the built-in display, with `targetTimestamp` steps that never vary. Paused, it fires nothing, and it resumes within one frame. `CACurrentMediaTime` and `CLOCK_UPTIME_RAW` agree. | measured |
| The MX wheel's events carry 1 detent each up to 36 events per second, and 1 to 3 in a free spin at 121 events per second. Their line delta is accelerated, up to 13 lines per event. | measured |
| The MX pointer moves 0.25 to 0.30 points per sensor count below 400 counts a second, 0.33 at 400 to 800, 0.43 at 800 to 1600, 0.59 at 1600 to 3200 and 0.94 at 3200 to 6400 (medians of 50 ms windows). The hand moves at a median 890 counts a second, and the median gain from 200 to 3200 counts a second is 0.40, 0.41 with 100 ms windows. From 20,257 pointer reports over 23 minutes of the user's own use, read passively from the MX's HID reports with the pointer position at each, away from screen edges. The rise is macOS acceleration (`HIDMouseAcceleration` 0.6875, `HIDPointerResolution` 400 dpi on this service). | measured |
| HID++ raw movement counts in the same sensor counts as the HID pointer report. | sourced (Solaar, logiops), not measured |
| The 2.4G mouse's receiver (USB, `0x1EA7:0x0002`, no product name) has two IOHIDDevice interfaces. Its pointer interface has primary usage mouse and usage pairs mouse, pointer, consumer and system control (1:0x80), with event service 0x10005214e. Its keyboard interface has only the keyboard pair, with event service 0x100052151. On a plug-in the pointer interface matched first. | measured |
| The built-in trackpad is a second IOHIDDevice of the built-in keyboard's device, with the same missing vendor and product ids, `Built-In` 1, location 0x6F and FIFO transport. Its primary usage is mouse, and its usage pairs include digitizer touchpad (0x0D, 0x05). | measured |
| The MX's left and right buttons (0x50, 0x51) are not divertable. The middle, back, forward, gesture, top and thumb buttons are, with raw movement. | measured |
| A `flagsChanged` event posted at the HID tap sets `hidSystemState`, but the next hardware event puts the real state back: 20 to 40 ms later while the hand moves the MX, so a click in the hold came without the modifier. | measured |
| An other-button press (`otherMouseDown`) carries no IOHIDEvent, so its sender reads 0, while the same mouse's left and right clicks carry its event service. | measured |
| Turning an event tap off with `CGEventTapEnable` sends that tap a `tapDisabledByUserInput` event. | measured |

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
