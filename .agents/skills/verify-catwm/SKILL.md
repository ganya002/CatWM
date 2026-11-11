---
name: verify-catwm
description: Drive the real CatWM app (macOS tiling window manager) to prove that a change works. It builds this worktree, starts it as a separate named instance next to the user's CatWM, opens test windows on an empty workspace, runs commands through the catwm socket CLI and saves state JSON, tiling dumps, logs and screenshots as evidence. Use it after a change to tiling, layouts, focus, workspaces, floating, config or the control commands, when a unit test is not enough proof.
---

# Verify CatWM

CatWM is a menu bar app with no main window. A user touches it through key binds, the menu bar and the windows that it moves. An agent touches it through the `catwm` CLI. The CLI sends one command to the running app through a Unix socket, and it runs the same command registry as the key binds (`docs/internals/control.md`, `Resources/AgentDocs/cli.md`).

All scripts are in `.agents/skills/verify-catwm/scripts/`. Run them from the worktree root. `S=.agents/skills/verify-catwm/scripts` in the examples below.

## Read this first: each worktree runs its own instance

- The environment variable `CATWM_INSTANCE=<id>` gives a CatWM its own instance. The id is 1 to 24 characters of `a-z`, `0-9` and `-`. An instance has its own config folder `~/.config/catwm/instances/<id>/` (config, socket and pid file), its own log `~/Library/Logs/CatWM-<id>.log` and its own defaults. The CLI with the same `CATWM_INSTANCE` talks to that instance.
- The scripts use `INSTANCE=verify-<worktree folder name>` (cut to 24 characters). Set `INSTANCE` before a script to use another id. `env.sh` exports `CATWM_INSTANCE`.
- `launch.sh` does not stop the user's CatWM. With `CATWM_INSTANCE` set, `build.sh` and `AppDelegate.closePreviousInstances` stop only the CatWM in the pid file of that instance.
- A named instance does not register a login item, link the `catwm` command, check for updates, send crash or performance reports, show onboarding, tips or What's New, or run migrations. Its menu bar icon shows the id in the tooltip.
- Without a window scope, a named instance tiles all windows and reads all key presses, the same as the user's CatWM. So two instances move the same windows. Always verify a change in the running app. When the test needs the whole Mac (Desktops, focus), run `launch.sh` without a scope inside `with-lock.sh`. Do not ask first and do not hand back an unverified fix.
- `CATWM_SCOPE=pids:<pid>,<pid>...` makes the instance manage only the windows of these pids. A scoped instance does not use macOS Desktops, does not read key presses (`CATWM_KEYS=on` turns them on), does not change Caps Lock and does not move the pointer. A bad value stops CatWM with exit code 2, and so does pid 1. The instance quits when every pid in the scope has exited, so scope it to a process that lives as long as the test (`$$`, never `$PPID`). Read "Window scope" in `docs/internals/control.md`.
- A scoped instance writes a claim file (`~/.config/catwm/instances/<id>/scope`). The user's CatWM leaves out the claimed pids, but only if it is a build with this change. An older build of the user's CatWM still tiles the test windows, and two instances then write the same frames. Before a live test, check the build of the user's CatWM (`ps -o command= -p <pid>`).
- If the user is typing or presenting, do not start.

## Scoped run

Use a scoped run when the test needs only its own windows. Open the test windows in your own process first (a small test app in `/tmp`, or `desk.sh start`), then:

```sh
$S/run-scoped.sh <pid>[,<pid>...] <command> [args...]
$S/run-scoped.sh --no-build "$APP_PID" sh -c 'build/CatWM.app/Contents/MacOS/CatWM windows --json'
```

It builds the worktree (not with `--no-build`), starts the instance with `CATWM_SCOPE=pids:<pids>`, waits for `ping`, runs the command with `CATWM_INSTANCE` set and always stops the instance, also when the command fails. Its exit code is the exit code of the command. Only one run at a time can use an instance id. A second run with the same `INSTANCE` stops with exit code 1 while the first run or its instance runs. It also stops when the instance of `launch.sh` runs. `launch.sh` takes the same lock (`lock_instance` in `env.sh`), so it stops with exit code 1 while a run uses its instance id. Set `INSTANCE` to another id to run two at the same time.

Permissions: macOS gives Accessibility to the "responsible process". `run-scoped.sh` starts CatWM as a child process, so the instance gets the permissions of the app that runs your shell. An instance that `open -n` starts (`launch.sh`) is its own responsible process and needs its own permission in System Settings.

## Host lock

Some tests need state that the whole Mac shares: the focused app, the macOS Desktops, key presses, the pointer, Caps Lock. Only one agent at a time can do such a test. Run it in the host lock:

```sh
$S/with-lock.sh $S/run-scoped.sh <pid> <command>
```

`with-lock.sh` waits until no other agent holds the lock, runs the command and releases the lock. The lock is a `flock(2)` on `~/Library/Caches/CatWM-verify/host.flock` (`lockf`). The kernel releases it when the agent stops, also on `kill -9`, so a stale lock cannot stay. `host.flock.owner` tells who holds the lock. After `LOCK_TIMEOUT` seconds (default 600) it stops with exit code 75. Then ask the user. Do not delete `host.flock`.

| Test | Lock |
|---|---|
| layout, tiling, float, frames, `windows`, `dump`, config of a scoped instance | not necessary |
| focus, `CATWM_KEYS=on`, key presses, Desktops, `launch.sh` without a scope | necessary |

## Launch

```sh
$S/launch.sh
```

It does these steps:

1. It runs `./build.sh --dev` (lint, debug build, schema, clients, `build/CatWM.app`) with `CATWM_INSTANCE` set. The build log is `~/Library/Caches/CatWM-verify/<instance>/build.log`. A lint failure stops the launch. Fix the lint error.
2. It makes the evidence folder `~/Library/Caches/CatWM-verify/<instance>/runs/<UTC time>/` and writes `commit.txt` (HEAD and `git status`).
3. It runs `open -n -g --env CATWM_INSTANCE=<instance> build/CatWM.app --args --verbose --unscoped`.
4. Ready means: `catwm ping` answers with a pid whose executable is `build/CatWM.app/Contents/MacOS/CatWM`, and `status` shows `trusted` and `running` as `true`.

If it stops with "not trusted", this build has no Accessibility permission. Only the user can grant it: System Settings > Privacy & Security > Accessibility > CatWM. Then run `doctor.sh`. Do not try to go around TCC.

A new instance starts with the default config in its own folder. Do not delete or replace `~/.config/catwm/catwm.conf` or the other files of the user's CatWM. A first-run check (onboarding) needs a separate macOS user account, which this skill does not cover.

## Doctor

```sh
$S/doctor.sh
```

It is read-only. It shows which CatWM processes run, and it fails when:

- the instance does not run (its pid file has no live pid of this worktree's build),
- the socket answers from a pid that is not the pid in the pid file,
- the pid is not the one `launch.sh` started,
- the build number in `Info.plist` is not `git rev-list --count HEAD`,
- `trusted`, `running` or `tilingEnabled` is false.

Run it first when a command does nothing, when a result looks wrong, or when you come back to a run.

## Drive

Use the build's own binary as the CLI: `CLI=build/CatWM.app/Contents/MacOS/CatWM`. The user's `catwm` link can point to another copy. Add `--json` for compact JSON and parse it with `jq`. `$CLI help` lists all commands, and `$CLI help <command>` shows the arguments. Exit code `0` means the command ran, `1` means it was refused or CatWM does not run, and `2` means the arguments are wrong.

Test windows: `$S/desk.sh start [count]` goes to a new workspace (the number after the last workspace of the display) and opens `count` (default 4) scratch files `verify-1.txt` and up in a NEW TextEdit process. The user's own TextEdit is not touched. All test windows belong to that process, `DESK_PID` in the state file. Select them by `pid`. The script gives a test window the focus with `cyclenext`. The user's windows stay parked on their own workspace. `$S/desk.sh stop` quits that TextEdit process and goes back.

Do not use the onboarding practice windows (`CatWM practice`) as test windows. CatWM floats every window of its own bundle (`WindowManager.shouldFloat`), except during the tour, so they never tile.

Each workspace is a macOS Desktop. When you show workspace N, CatWM makes the missing Desktops up to N, and it removes the empty ones when you leave. Use the next free number, not a high number such as 9.

```sh
. $S/env.sh                                    # sets CLI, RUN, DESK_PID and the other state values
$CLI windows --json | jq --argjson p "$DESK_PID" '[.[] | select(.pid == $p)]'
$CLI layout tall
$CLI dump                                      # each tiled window: target, actual, OK or MISMATCH
```

Commands act on the focused window. Before a window command, check `focused` in `windows --json`. Commands run asynchronously: frames animate at 120 Hz. Wait for the state, do not sleep a fixed time. Poll `windows --json` or `dump`, or subscribe to an event first: `$CLI events layout.changed tiling.changed > $RUN/events.jsonl &` (record `$!` and kill that pid when you are done).

For Python, use the generated client and the test helpers in `Clients/python/catwm/testing.py` (`connect`, `wait_for_window`, `wait_until`, `Events`):

```sh
python3 -I -c 'import sys; sys.path.insert(0, "Clients/python")
from catwm import CatWM
from catwm.testing import Events
c = CatWM()
with Events("layout.changed") as e:
    c.layout("wide"); print(e.wait("layout.changed", timeout=3))'
```

Key binds and menus need real key presses. The user path for a key bind is the event tap, so a proof for a key bind change needs a key press: `osascript -e 'tell application "System Events" to key code 48 using command down'`. That needs Accessibility for the terminal app, and it acts on whatever has the focus. Ask the user before you send key presses. For most changes, the CLI command is the same dispatcher that the key bind calls, and it is enough.

The feature map is in `features/README.md`. Before you claim that a feature works, drive every entry point that its file lists.

## Evidence

```sh
$S/evidence.sh before    # before the action
$CLI layout wide
$S/evidence.sh after     # after the action
```

`evidence.sh <label>` writes `<label>.status.json`, `<label>.windows.json`, `<label>.workspaces.json`, `<label>.dump.txt` and `<label>.png` (full screen, `screencapture -x`) to the run folder. It also updates `catwm.log`, which holds the CatWM log lines since launch. The screenshot shows the user's screen. It can show private content, so do not upload it anywhere without asking.

Proof rules:

- Use the real user path: a dispatcher through the socket, a key press, a config edit and `reload`. Do not call internal setters. The `dev` commands (`grabtest`, `modefx`, `panelfx`, `poststyle`, `intro`, `introlab`) are only previews.
- Capture the state before and after the action, not only the end state.
- Check the side effects too: the frames in `dump` (each tiled window must be `OK`, not `MISMATCH`), the file `$CONF` after `config.set`, and the log lines (`config:`, `ipc:`, `tiling:`).
- For a speed change, use the timings in the log (`tiling: refresh windows 6 17.7ms`, `native workspaces: request to motion ...`), not your impression.
- A screenshot shows the result, and JSON or `dump` proves it. Give both.

## Cleanup

```sh
$S/cleanup.sh
```

It closes the test windows, goes back to the workspace from before `desk.sh start` and quits the verify instance through `catwm exit` (CatWM puts parked windows back first). It stops only the pid that `launch.sh` started. It never kills by process name, and it does not touch the user's CatWM. The evidence folder stays. Give the user its path.

Run `cleanup.sh` after each failed attempt too. If a script stopped halfway, `doctor.sh` shows what still runs.

## Helpers

| Script | Use |
|---|---|
| `scripts/run-scoped.sh [--no-build] <pids> <command>` | build, start a scoped instance, run the command, stop the instance |
| `scripts/with-lock.sh <command>` | run the command in the host lock |
| `scripts/launch.sh` | build, start the named instance, wait until it is ready |
| `scripts/doctor.sh` | read-only health check |
| `scripts/desk.sh start [count]\|stop` | TextEdit test windows on a new workspace |
| `scripts/evidence.sh <label>` | save state, dump, log and screenshot |
| `scripts/cleanup.sh` | close the test windows, quit the named instance, keep the evidence |
| `scripts/env.sh` | `. scripts/env.sh` loads `CLI`, `RUN`, `DESK_PID`, `INSTANCE`, `CONF` and the paths into your shell, and exports `CATWM_INSTANCE` |
