# CatWM verification map

This folder is the maintained source for verifying what a CatWM user sees. Read this index before you drive the app, then use the matching feature file as the recipe. `S=.agents/skills/verify-catwm/scripts` and `CLI=build/CatWM.app/Contents/MacOS/CatWM` in every file.

## Baseline preconditions

- The user said yes to replacing their running CatWM for this run.
- `$S/launch.sh` ran in this worktree, and `$S/doctor.sh` prints `doctor: OK`.
- `$S/desk.sh start` opened 4 TextEdit test windows (`verify-1.txt` to `verify-4.txt`) on a new workspace, and a test window has the focus.
- Each Bash call starts a new shell. Begin each call with `. $S/env.sh` to load `CLI`, `RUN` and `DESK_PID`.

## Driving conventions

- Select test windows by `pid == DESK_PID`. Do not select by position in the list.
- Check which window has the focus before a window command: `$CLI windows --json | jq '.[] | select(.focused)'`.
- The key binds below are the default binds. The config of the instance (`$CONF` from `env.sh`) can bind other keys. Read it before you send a key press.
- Wait for a state, not for a time: poll `windows --json` or `dump`, or start `$CLI events <name>` before the action.
- Put back each setting that you change (layout, ratio, config options). The config file is the user's real config.

## Proof and skip reporting

- Run `$S/evidence.sh <label>` before and after each action that you prove. Name the label `<feature>-<sub-feature>-before|after`.
- A layout or frame proof needs `dump` with `OK` on each tiled test window, and the frames in `windows --json`. A screenshot alone is not proof.
- A command proof gives the command, the output and the exit code.
- A config proof reads the value back with `config.get`, and reads the line in `catwm.conf`.
- If you cannot reach an entry point (for example, a key press without Accessibility for the terminal), report it as not verified, with the command that you tried. Do not report it as verified through a different entry point.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph about the behavior that the user sees. Then it has these four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with the catwm CLI`, and `Gotchas`.

## Features

- [Layouts](./layouts.md): set, cycle and resize the layout of a workspace.
- [Focus and move](./focus-and-move.md): move the focus and the windows in a direction, or cycle through them.
- [Workspaces](./workspaces.md): show a workspace, and send a window to another workspace.
- [Floating and fullscreen](./floating-and-fullscreen.md): take a window out of the tiling, or let it fill the screen.
- [Config and reload](./config-and-reload.md): change an option and read the config again.

Not mapped yet: the Overview (`sort`), the window switcher, window mode and its effects, the keyboard help, tabs (`moveintogroup`), templates, notifications, Settings and onboarding. Add a file when you verify one of them.
