# Troubleshooting

## Where to look

- Log: `~/Library/Logs/CatWM.log` (plain text, truncated past ~2 MB). An instance that runs with `CATWM_INSTANCE=<id>` writes `~/Library/Logs/CatWM-<id>.log`. Config problems appear as `config: …`; CLI commands as `ipc: …`.
- More detail: relaunch with `open build/CatWM.app --args --verbose`.
- State snapshot: `catwm dump`, then read the log.

## Common problems

| Symptom | Cause / fix |
|---|---|
| ⚠️ in the menu bar, nothing tiles | Accessibility not granted, or revoked by a rebuild. Settings opens; click **Reset Permission**, then enable CatWM again in System Settings → Privacy & Security → Accessibility. Ad-hoc-signed builds lose the grant on every rebuild. |
| Keybinds do nothing but tiling works | Input Monitoring missing (needed for raw Caps Lock). Grant it when the permission guide asks. |
| CLI exits 0 but nothing happens | CatWM isn't running, or the command was refused (`exec`, `launch`) or malformed. Read the log. |
| Config edits ignored | Run `catwm reload`; check the log for `config: unknown option …` / `needs a number`. Settings UI edits can overwrite hand edits. |
| "Config: N error(s)" HUD | See `config:` lines in the log. |
| Window won't tile | It may be floating (`floating` list, `float-small-windows`, not resizable). `dump` lists floating windows. |
| Window is off-screen | It is parked on a hidden workspace. Switch to that workspace, or quit CatWM to restore all parked windows. |
| `workspace N` doesn't switch (Spaces mode) | Enable "Switch to Desktop N" shortcuts on Ctrl+N, or use `virtual-workspaces = true`. |
| Swipe binds also trigger macOS gestures | Disable the system gesture; CatWM can't intercept swipes. |
| A template does not save or reopen browser tabs or folders | `template-app-scripting` is off, or Automation access for that app is off. Turn it on in Settings → Templates → **Save tabs and folders**, then allow CatWM in System Settings → Privacy & Security → Automation, and update the template. The log shows `template: app state for N of M windows`. |
| Stuck in window mode | Press the mode's exit key (usually Esc), click anywhere, or `catwm dispatch submap reset`. |

## Settings pointers

Menu bar → **Settings…** (⌘,): General (permissions, login item, updates, beta channel), Scrolling, Windows, Motion, Shortcuts. ⌘K searches every setting including Advanced sections. **Undo All Changes** reverts to the state when the window opened.

Updates ship via Sparkle/Amore. Menu bar → Help → Check for Updates…. The beta channel is Settings → General → Updates → **Include beta releases**.
