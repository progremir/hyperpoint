# Settings window

Settings… (⌘,) opens a preferences window with a toolbar of five tabs: General, Hyper Key, Buttons, Scrolling and Devices. Each tab is one page at a fixed 640 pt width, and the window's height animates to the page. Pages are two-column forms: right-aligned labels on the left, controls and a small explanation on the right, dividers between groups. Every edit saves to `~/.config/hyperpoint/config.json` through the same parser as a hand edit, and the engine re-applies.

## Sub-features

- `settings-open` opens and activates the window from the menu, on the tab the user had open last.
- `settings-tabs` renders each tab and animates the window's height between them.
- `settings-device` shares one Device popup between Buttons and Scrolling. New mice say "(New)"; ignored devices are not listed.
- `settings-rules` edits, adds and removes profile rules with pickers limited to valid choices.
- `settings-graph` edits the speed curve by dragging points, saving on mouse-up.
- `settings-devices` renames a profile, forgets it after a confirmation, ignores a new device and stops ignoring one.
- `settings-save` writes the file and the engine re-applies; the window is read-only while the file is invalid.

## How to get to it (user POV)

- Menu bar icon › Settings… or ⌘, while the menu is open.
- Toolbar: General (login item, how to grant permissions, config file, log), Hyper Key (key, keyboards, how it works), Buttons (Device popup, status and Re-apply, rules, gestures), Scrolling (Device popup, smooth scrolling, speed graph, glide, hold to scroll, not yet available), Devices (every device, Forget, Ignore, Stop Ignoring).

## Driving it with verify.sh

Preconditions:

- Hyperpoint running and settled.
- A copy of the user's config saved to the evidence directory before any edit.

- **Every tab renders.** Run `verify.sh settings-shots`. Under `settings/` it writes one PNG per tab at the window's own size, toolbar included, then the same set again in dark mode: `01-general.png`, `02-hyper-key.png`, `NN-buttons-<mouse>.png` and `NN-scrolling-<mouse>.png` for each mouse (such as `03-buttons-mx-master-3.png`), and `NN-devices.png` last, each with an `-dark.png` twin. A page taller than the screen gets a second PNG, `NN-name-end.png`, scrolled to its end. Check the PNG heights differ per tab, the selected tab is highlighted, and the Scrolling PNGs show the speed graph, the measured-range labels, the glide sliders and the Hold to scroll section.
- **Height animates.** `settings-shots` also prints the window's on-screen heights, sampled every 15 ms (`settings-heights.txt`). Every tab switch and every Device change shows a run of intermediate heights, not a single jump.
- **Last tab.** `defaults write dev.emir.hyperpoint settingsTab devices`, then `settings-shots`: the heights start by settling at the Devices page's height before General's, and `defaults read dev.emir.hyperpoint settingsTab` is `devices` again afterwards.
- **Edit saves.** Ask the user (or drive by accessibility if available) to move "Glide after you stop" and release. `verify.sh log 1m` shows a settings save and `reasons=configChanged … applied` for every device. `diff` the saved copy against the live file: only that key changed (the first save also rewrites formatting and the old speed keys as `curve`).
- **Ignore and Forget.** With the user's consent and a device without a profile connected (Karabiner's virtual keyboard is one), Ignore it on Devices: it leaves the Hyper Key list and the Device popup, and `ignored` in the file gains its match. Stop Ignoring removes it again. Forget asks first, then removes the profile.
- **Invalid file.** With the user's consent, write an out-of-range value by hand. The menu shows `Config file has an error`, every tab shows the error and disables editing, and `verify.sh state` is unchanged. Restore the saved copy.

## Gotchas

- `screencapture` fails in this shell (no Screen Recording grant), so the app renders its own pages. The window is not key during the shots, so the selected tab and the title draw in their inactive colors.
- The first save from the window rewrites the whole file in the app's format. Tell the user before the first edit.
- The engine leaves ignored devices out of its status, so an ignored device is named only if this run of the app saw it as new. Otherwise the Devices tab names it by vendor and product id.
