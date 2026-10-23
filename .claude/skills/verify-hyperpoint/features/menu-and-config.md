# Menu and config reload

The menu-bar menu shows Active or Needs attention, each device's state, the last reconnect, and Re-apply, Pause, Open Config File, Settings… and Quit. Saving the config file by hand reloads it; an invalid file keeps the last good settings and says why.

## Sub-features

- `menu-state` shows Active, or Needs attention with notices for missing permissions and config errors.
- `menu-devices` shows each device's connection and apply state.
- `menu-reapply` re-applies every device (⌘R).
- `menu-pause` returns every device to neutral until resumed.
- `config-reload` applies a hand edit on save; an invalid edit keeps the last good config.

## How to get to it (user POV)

- Click the Hyperpoint icon in the menu bar.
- Edit `~/.config/hyperpoint/config.json` in an editor and save.

## Driving it with verify.sh

Preconditions:

- Hyperpoint running and settled.
- A copy of the user's config saved to the evidence directory.

- **Menu state.** Run `verify.sh doctor`. The `menu:` line lists `state=`, the notices and every device's status. It is the same text the menu renders.
- **Re-apply.** Ask the user to choose Re-apply Settings Now. `verify.sh log 1m` shows `reasons=manual … applied` for each device.
- **Pause.** Ask the user to choose Pause Hyperpoint. `verify.sh state` shows empty key maps and every MX control native. After Resume, `verify.sh state` matches the profile again.
- **Hand edit.** Change one value in the live file and save it. `verify.sh log 1m` shows `reasons=configChanged … applied`. Restore the saved copy and confirm the same.
- **Invalid edit.** Write an out-of-range value (for example `"brake": 50`). `doctor`'s menu line shows `Config file has an error`, and `verify.sh state` is unchanged. Restore the copy; the notice clears.

## Gotchas

- Range errors name the path (for example `devices[0].scrolling.smooth.brake`) in the log, not in the menu line.
- Pause is runtime state and does not survive a relaunch. A relaunch always comes back Active.
- The `menu` log category logs every state change. Check that the line's pid is the instance you launched.
