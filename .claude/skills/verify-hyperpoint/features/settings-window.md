# Settings window

Settings… (⌘,) opens a preferences window with a toolbar of five tabs: General, Hyper Key, Buttons, Scrolling and Devices. Each tab is one page at a fixed 640 pt width, and the window's height animates to the page. Pages are two-column forms: right-aligned labels on the left, controls and a small explanation on the right, dividers between groups. Every edit saves to `~/.config/hyperpoint/config.json` through the same parser as a hand edit, and the engine re-applies.

## Sub-features

- `settings-open` opens and activates the window from the menu, on the tab the user had open last.
- `settings-tabs` renders each tab and switches like a native preferences window: the new page stays hidden while the window animates to its height over 0.18 s, then shows. A page that grows in place (another mouse, a rule added) hides the same way, and one that shrinks stays in view. It is never clipped or scrolling unless it is taller than the screen.
- `settings-device` shares one Device popup between Buttons and Scrolling. New mice say "(New)"; ignored devices are not listed.
- `settings-rules` edits, adds and removes profile rules with pickers limited to valid choices.
- `settings-graph` edits the speed curve by dragging points, saving on mouse-up.
- `settings-setup` sets a new device up from the Devices, Buttons, Scrolling or Hyper Key tab: the button applies the best preset, and its menu offers the other presets, an empty profile for a mouse and a copy of another profile.
- `settings-devices` renames a profile, forgets it after a confirmation, ignores a new device and stops ignoring one.
- `settings-save` writes the file and the engine re-applies; the window is read-only while the file is invalid.

## How to get to it (user POV)

- Menu bar icon › Settings… or ⌘, while the menu is open.
- Toolbar: General (login item, how to grant permissions, config file, log), Hyper Key (key, keyboards, how it works), Buttons (Device popup, status and Re-apply, rules, gestures), Scrolling (Device popup, smooth scrolling, speed graph, glide, hold to scroll, not yet available), Devices (every device, Set Up, Forget, Ignore, Stop Ignoring).

## Driving it with verify.sh

Preconditions:

- Hyperpoint running and settled.
- A copy of the user's config saved to the evidence directory before any edit.

- **Every tab renders.** Run `verify.sh settings-shots`. Under `settings/` it writes one PNG per tab at the window's own size, toolbar included, then the same set again in dark mode: `01-general.png`, `02-hyper-key.png`, `NN-buttons-<mouse>.png` and `NN-scrolling-<mouse>.png` for each mouse (such as `03-buttons-mx-master-3.png`), and `NN-devices.png` last, each with an `-dark.png` twin. A page taller than the screen gets a second PNG, `NN-name-end.png`, scrolled to its end. Check the PNG heights differ per tab, the selected tab is highlighted, and the Scrolling PNGs show the speed graph, the measured-range labels, the glide sliders and the Hold to scroll section.
- **Tab switches.** Run `verify.sh settings-switches` with the window open or closed. It presses every tab from every other tab (20 switches), switches the Device popup on Buttons and Scrolling to the other mouse and back, and opens Scrolling on the shortest screen when the page is taller than it, then puts the window back on its tab and position. `settings-switches.txt` has every sample and a verdict per change. A switch passes when the height moves one way over 0.1 to 0.3 s, the incoming page is never in the window clipped or with a scroll bar, and it shows within 0.35 s. A Device change passes when the height animates the same way, starts within 50 ms of the first sample that sees the page change, and the page is never clipped or scrolling. The change itself lands about 0.4 s after the press, which is the menu item's selection blink. The page past the screen passes when the window stops at the screen's visible height and the page shows there with a scroll bar.
- **Height animates.** `settings-shots` also prints the window's on-screen heights, sampled every 15 ms (`settings-heights.txt`). Every tab switch and every Device change shows a run of intermediate heights, not a single jump.
- **Last tab.** `defaults write dev.emir.hyperpoint settingsTab devices`, then `settings-shots`: the heights start by settling at the Devices page's height before General's, and `defaults read dev.emir.hyperpoint settingsTab` is `devices` again afterwards.
- **Edit saves.** Ask the user (or drive by accessibility if available) to move "Glide after you stop" and release. `verify.sh log 1m` shows a settings save and `reasons=configChanged … applied` for every device. `diff` the saved copy against the live file: only that key changed (the first save also rewrites formatting and the old speed keys as `curve`).
- **Set up from a fresh install.** With the user's consent, save their config to the evidence directory, run `verify.sh quit`, move the file away and run `verify.sh launch`. The new file has `"devices": []`, and `verify.sh state` shows empty key maps and every MX control native. On Devices each connected device is new with a Set Up button: "Set Up as MX Master 3" for the MX and "Set Up with Hyper Key" for each keyboard. Run `verify.sh set-up "Set Up as MX Master 3"` and `verify.sh set-up "Set Up with Hyper Key"` once per keyboard. The log has `saved devices += … from preset …` for each press, and `verify.sh state` then matches the read-back taken with the user's file. To check the menu, remove a profile from the test file and run `verify.sh set-up "Set Up as MX Master 3" "Nothing yet"`: the file gains a profile with only its match and name. Put the saved file back byte for byte (`cmp`) and check `state` again.
- **Ignore and Forget.** With the user's consent and a device without a profile connected (Karabiner's virtual keyboard is one), Ignore it on Devices: it leaves the Hyper Key list and the Device popup, and `ignored` in the file gains its match. Stop Ignoring removes it again. Forget asks first, then removes the profile.
- **Invalid file.** With the user's consent, write an out-of-range value by hand. The menu shows `Config file has an error`, every tab shows the error and disables editing, and `verify.sh state` is unchanged. Restore the saved copy.

## Gotchas

- `settings-switches` reads the page through Accessibility, which waits for the app's main thread, so it samples the window's height on a separate thread. The window server's height lags the app's by about a frame, so a page's clipping is judged against the app's own window frame.
- Heights the app never set, such as a smooth 423 to 138 over 0.7 s, come from something else scaling windows on screen, such as Mission Control. Rerun when nobody is using the Mac.
- `screencapture` fails in this shell (no Screen Recording grant), so the app renders its own pages. The window is not key during the shots, so the selected tab and the title draw in their inactive colors.
- The first save from the window rewrites the whole file in the app's format. Tell the user before the first edit.
- Hyperpoint has no Dock icon, and raising its window through Accessibility does not make it the active app, so its fields cannot take focus and a posted key event goes to whatever app is frontmost. Activate it with `osascript -e 'tell application id "dev.emir.hyperpoint" to activate'`, check `NSWorkspace.shared.frontmostApplication` is Hyperpoint right before posting any key, and give focus back to the user's app afterwards. Prefer Accessibility actions (`AXFocused`, `AXConfirm`) to key events.
- The engine leaves ignored devices out of its status, so an ignored device is named only if this run of the app saw it as new. Otherwise the Devices tab names it by vendor and product id.
