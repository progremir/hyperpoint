---
name: verify-hyperpoint
description: Drive the real Hyperpoint menu-bar app on this Mac and prove a change works. It covers the hyper key, MX Master 3 buttons over HID++, smooth scrolling, hold to scroll and the settings window. Use after changing Hyperpoint, before claiming a fix or feature works, or when its behavior on the real devices is in doubt.
---

# Verify Hyperpoint

Hyperpoint is a menu-bar app (`LSUIElement`) with no window until Settings opens. Most of what it does is invisible state on devices: a `hidutil` key mapping per keyboard, HID++ firmware state on the MX Master 3, and an event tap that rewrites keys and scrolls. Proof therefore comes from reading that state back and from what other processes observe, not from screenshots of the app.

Everything runs through `verify.sh` in this directory. Each run writes its evidence to `$REPO/.verify-evidence/<run>/`, which is gitignored and survives cleanup. Set `HYPERPOINT_VERIFY_RUN=<name>` to put several commands in one evidence directory.

```bash
export HYPERPOINT_VERIFY_RUN=hyper-$(date +%H%M%S)
.claude/skills/verify-hyperpoint/verify.sh help
```

## One instance only

Hyperpoint drives shared hardware: the user's keyboards, their mouse and the system event stream. Two instances would fight over the same HID++ controls and both rewrite keys. Never start a second copy, and never run a build from `.build/` directly. Verification replaces the user's running instance with the build under test, then leaves that build running so their hyper key and mouse keep working. Tell the user before you quit their instance.

Conflicting apps change results: Karabiner-Elements seizes keyboards (so `hidutil` mappings have no effect while it runs), and BetterMouse diverts the same MX controls. `doctor` lists them. Do not quit them yourself; ask the user.

## Launch

1. `verify.sh build` quits Hyperpoint through its own quit path, then runs `scripts/bundle.sh`. That runs the layer check, builds release, signs with the Apple Development identity and installs `~/Applications/Hyperpoint.app`. It refuses an ad-hoc signature, because a cdhash requirement resets the permission grants on every build.
2. `verify.sh launch` opens the app and waits for a settled menu line from this pid (`state=Active` or `state=Needs attention`, not `Applying…`). Ready means every present device has finished its first apply.

First launch on a fresh Mac needs the user to grant Accessibility and Input Monitoring to `~/Applications/Hyperpoint.app` in System Settings › Privacy & Security. Grants survive rebuilds because the designated requirement has no cdhash. Without them the menu shows `Needs attention` with a permission notice, and nothing is applied. That is a valid, observable state, not a launch failure.

The config lives at `~/.config/hyperpoint/config.json`, and a missing file is created from `Config.default`. Never edit the user's file to stage a test without telling them. Their profile is real. If a journey needs a different config, save theirs to the evidence directory first and restore it byte for byte afterwards.

## Doctor

`verify.sh doctor` is read-only. It prints:
- the repo HEAD and branch;
- the installed binary's build time against the newest commit, so a stale install is visible;
- the running pid;
- the designated requirement, flagging a cdhash;
- the last menu state line;
- conflicting apps.

Drive only when the pid exists, the binary is newer than the commit under test, and the menu line is settled.

## Drive

| Command | What it does | Needs |
| --- | --- | --- |
| `verify.sh state` | `hidutil` key maps for the built-in and Magic keyboards, and read-only HID++ state of the MX (`helpers/hidpp-state.swift`, get requests only) | the MX connected; this shell able to open the device |
| `verify.sh hyper-check [n]` | posts F18 then F16 at the HID tap n times; counts ⌘⌃⌥⇧F16 Carbon hotkey fires and modifier state left held | `HyperpointProbe.app` with Accessibility |
| `verify.sh record posted` | 40 s of scroll events Hyperpoint posts: per-frame points, fixed-point value, `NSEvent.scrollingDeltaY`, phase, frame gaps, leaked line events | the user scrolling the MX wheel |
| `verify.sh record wheel` | 45 s of raw wheel input: sender id, raw detents per event, macOS's accelerated lines | the user scrolling |
| `verify.sh record senders` | 90 s of pointer event sender ids grouped every 2 s | the user using each pointer device |
| `verify.sh record hold` | 45 s of what apps receive during hold to scroll: posted scrolls on both axes with scroll and momentum phases, the pointer position at each, and right and other button events, replayed or native | the user holding a button and moving the mouse |
| `verify.sh settings-shots` | relaunches with `-snapshotSettings <dir>`; the app renders every settings tab to PNG itself, in light then dark, while `helpers/window-heights.swift` records the window's on-screen height to `settings-heights.txt` | none (the shell has no Screen Recording grant, so `screencapture` fails here) |
| `verify.sh settings-switches` | presses every settings tab from every other tab, switches the Device popup on Buttons and Scrolling, and opens Scrolling on the shortest screen, while `helpers/tab-switches.swift` samples the on-screen window height and the incoming page (clipped, scroll bar) at 120 Hz; one verdict line per change in `settings-switches.txt` | Settings open or openable from the menu; this shell's Accessibility grant |
| `verify.sh log [10m]` | Hyperpoint's unified log (`subsystem dev.emir.hyperpoint`, categories `devices` and `menu`) | none |

The probe (`helpers/probe.swift`) installs as `~/Applications/HyperpointProbe.app`, signed with identifier `dev.emir.hyperpoint.probe`, so its Accessibility grant survives rebuilds. If it reports `accessibilityTrusted=false`, stop and ask the user to grant it.

Anything that needs a physical action (a gesture, a wheel spin, a power cycle) is the user's to perform. State exactly what to do, in order, with pauses. Start the recording, and have the user act while it runs. Never claim a physical behavior from unit tests or posted synthetic events alone. Synthetic scroll events carry no MX sender id, so Hyperpoint correctly ignores them.

Feature recipes are in [features/README.md](features/README.md).

## Evidence

Every proof needs both the action and the resulting state, from outside Hyperpoint:
- **Key maps:** a `hidutil --get` read-back.
- **Mouse state:** the `hidpp-state` read-back of the mouse's own firmware.
- **Hotkeys:** a Carbon hotkey in another process firing.
- **Scrolling:** what the session-level event stream delivered, frame by frame.
- **Menu:** the menu log line.
- **Settings window:** PNGs from `settings-shots`, and the per-switch verdicts from `settings-switches`.

The app's own log says what it attempted. The read-backs say what the device holds, and they are the proof. Tests and the log alone are not proof of device behavior.

## Cleanup

- Quit only through `verify.sh quit` (the app's quit path). It returns every device to neutral, with an empty key map and every MX control native, and records the key maps afterwards as evidence. Never `kill -9` Hyperpoint: a hard kill leaves Caps Lock mapped to F18 and the MX buttons diverted until the next launch clears them.
- End every run with the build under test **running**: `verify.sh launch` after any quit. The user depends on it.
- If a journey changed the MX firmware (SmartShift, hi-res wheel), restore the values from the `state` read-back taken first.
- Leave `.verify-evidence/` in place. It is the proof.
