# Troubleshooting

## Where to look

- Log: `~/Library/Logs/ouch.log` (plain text, truncated past ~2 MB). Config problems appear as `config: …`; CLI commands as `ipc: …`.
- More detail: relaunch with `open build/ouch.app --args --verbose`.
- State snapshot: `ouch dump`, then read the log.

## Common problems

| Symptom | Cause / fix |
|---|---|
| ⚠️ in the menu bar, nothing tiles | Accessibility not granted, or revoked by a rebuild. Settings opens; click **Reset Permission**, then enable Ouch again in System Settings → Privacy & Security → Accessibility. Ad-hoc-signed builds lose the grant on every rebuild. |
| Keybinds do nothing but tiling works | Input Monitoring missing (needed for raw Caps Lock). Grant it when the permission guide asks. |
| CLI exits 0 but nothing happens | Ouch isn't running, or the command was refused (`exec`) or malformed. Read the log. |
| Config edits ignored | Run `ouch reload`; check the log for `config: unknown option …` / `needs a number`. Settings UI edits can overwrite hand edits. |
| "Config: N error(s)" HUD | See `config:` lines in the log. |
| Window won't tile | It may be floating (`floating` list, `float-small-windows`, not resizable). `dump` lists floating windows. |
| Window is off-screen | It is parked on a hidden workspace. Switch to that workspace, or quit Ouch to restore all parked windows. |
| `workspace N` doesn't switch (Spaces mode) | Enable "Switch to Desktop N" shortcuts on Ctrl+N, or use `virtual-workspaces = true`. |
| Swipe binds also trigger macOS gestures | Disable the system gesture; Ouch can't intercept swipes. |
| Stuck in window mode | Press the mode's exit key (usually Esc), click anywhere, or `ouch dispatch submap reset`. |

## Settings pointers

Menu bar → **Settings…** (⌘,): General (permissions, login item, updates, beta channel), Layout, Windows, Motion, Shortcuts. ⌘K searches every setting including Advanced sections. **Undo All Changes** reverts to the state when the window opened.

Updates ship via Sparkle/Amore. Menu bar → Help → Check for Updates…. The beta channel is Settings → General → Updates → **Include beta releases**.
