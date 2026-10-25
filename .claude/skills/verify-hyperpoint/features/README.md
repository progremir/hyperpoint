# Hyperpoint verification map

This directory is the maintained source for verifying Hyperpoint's user-facing behavior. Read the index, then use the matching feature file as the recipe.

## Baseline preconditions

- The build under test is installed by `verify.sh build` and running from `verify.sh launch`, with the menu line settled.
- `verify.sh doctor` shows the expected branch, an install newer than HEAD's commit, no cdhash, and a settled menu line.
- Hyperpoint has Accessibility and Input Monitoring; HyperpointProbe has Accessibility.
- The user's real config at `~/.config/hyperpoint/config.json` is in force. Save a copy to the evidence directory before any journey that changes it.

## Driving conventions

- One Hyperpoint instance at a time; verification replaces the user's and leaves the build under test running.
- Physical actions (gestures, wheel, power cycles, Caps Lock presses) are asked of the user, with a recording running.
- Read device state with `verify.sh state`, never infer it from the log.
- Set `HYPERPOINT_VERIFY_RUN` once per journey so its artifacts share a directory.

## Proof and skip reporting

- Record the feature ID and entry point with every artifact.
- A journey that needs a quit app (Karabiner, BetterMouse) or an absent device (the 2.4G mouse unplugged) is reported as skipped with the unmet precondition, never as verified through another path.

## Features

- [Hyper key](./hyper-key.md) covers Caps Lock as ⌘⌃⌥⇧ per keyboard, tap-alone, quit and crash cleanup.
- [MX buttons and gestures](./mx-buttons.md) covers HID++ diverts, gestures, the top button, the thumb wheel and reconnect re-apply.
- [Smooth scrolling](./smooth-scrolling.md) covers the speed curve, the glide, frame timing and per-device attribution.
- [Hold to scroll](./hold-to-scroll.md) covers scrolling by holding the right button and moving, the pointer freeze from the press, the release glide and the right click it keeps.
- [Held keys](./held-keys.md) covers a mouse button held as a modifier or a shortcut, over HID++ and through the tap, and letting go when it is interrupted.
- [Mouse keys](./mouse-keys.md) covers the 2.4G mouse's Escape held as Right Option at the HID layer and its Return clicking ⌥⇧S through a carrier.
- [Settings window](./settings-window.md) covers every tab, the window height animating between them, editing rules and the speed graph, setting up, forgetting and ignoring devices, and saving through the config file.
- [Menu and config reload](./menu-and-config.md) covers the menu states, re-apply, pause, and invalid-config handling.
