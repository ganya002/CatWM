# CatWM: agent guide

CatWM is a macOS tiling window manager with its own workspaces, a plain-text config and animated window movement. It runs as a menu bar app. These files describe the **shipped product**, so an agent can operate and configure it for a user. They don't describe the source code.

Read in this order:

| File | Read it to |
|---|---|
| [cli.md](cli.md) | control a running CatWM from a shell (`dispatch`, `reload`, `dump`) |
| [python.md](python.md) | drive and test a running CatWM from Python: commands, waits and events |
| [config.md](config.md) | read or edit `~/.config/catwm/catwm.config.ts` (every option, value formats) |
| [keybinds.md](keybinds.md) | write `bind` lines: modifiers, keys, ranges, scroll/swipe, window mode |
| [dispatchers.md](dispatchers.md) | know what each command does and what args it takes |
| [workspaces.md](workspaces.md) | understand workspaces, displays and macOS Desktops |
| [troubleshooting.md](troubleshooting.md) | permissions, logs, and common failures |

## Facts to know first

- These docs ship inside the app at `CatWM.app/Contents/Resources/AgentDocs/`. `catwm docs` prints that folder.
- The app binary is also the CLI: `CatWM.app/Contents/MacOS/CatWM <command>`. A build from this repo lives at `build/CatWM.app`.
- Config file: `~/.config/catwm/catwm.config.ts` (created on first run, or converted from `catwm.conf`). Types: `catwm.d.ts` next to it. Saved config presets: `~/.config/catwm/configs.json` (managed by the Settings window; don't hand-edit).
- The Settings window and `config.set` never edit `catwm.config.ts`. They write `catwm.overrides.json`, which wins over the TypeScript file.
- CatWM needs the **Accessibility** permission. Without it nothing is tiled and no keybinds work.
- Default `$mod` is Option (`ALT`), not Command, so app shortcuts keep working.
- CatWM was previously named Hyprthyst (bundle ID `local.hyprthyst`) and then Ouch (bundle ID `local.ouch`). Its bundle ID is now `local.catwm`. Settings are migrated once.
