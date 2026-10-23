# Settings window

Settings… (⌘,) opens a window with General, Hyper key, and a page per device. Mice have Buttons and Scrolling and clicks tabs. Every edit saves to `~/.config/hyperpoint/config.json` through the same parser as a hand edit, and the engine re-applies.

## Sub-features

- `settings-open` opens and activates the window from the menu.
- `settings-pages` renders General, Hyper key, each device and the new-device page.
- `settings-rules` edits, adds and removes profile rules with pickers limited to valid choices.
- `settings-graph` edits the speed curve by dragging points, saving on mouse-up.
- `settings-save` writes the file and the engine re-applies; the window is read-only while the file is invalid.

## How to get to it (user POV)

- Menu bar icon › Settings… or ⌘, while the menu is open.
- Sidebar: General, Hyper key, then Devices.

## Driving it with verify.sh

Preconditions:

- Hyperpoint running and settled.
- A copy of the user's config saved to the evidence directory before any edit.

- **Every page renders.** Run `verify.sh settings-shots`. PNGs for General, Hyper key, each device's tabs and the keyboards appear under `settings/`. Open the scrolling PNG and check the speed graph, the measured-range labels and the glide sliders.
- **Edit saves.** Ask the user (or drive by accessibility if available) to move "Glide after you stop" and release. `verify.sh log 1m` shows a settings save and `reasons=configChanged … applied` for every device. `diff` the saved copy against the live file: only that key changed (the first save also rewrites formatting and the old speed keys as `curve`).
- **Invalid file.** With the user's consent, write an out-of-range value by hand. The menu shows `Config file has an error`, the window shows the error and disables editing, and `verify.sh state` is unchanged. Restore the saved copy.

## Gotchas

- `screencapture` fails in this shell (no Screen Recording grant), so the app renders its own pages. The glass sidebar renders blank in those PNGs; check it by eye or accessibility instead.
- The first save from the window rewrites the whole file in the app's format. Tell the user before the first edit.
- Karabiner's virtual keyboard appears as a new keyboard; there is no Ignore button yet.
