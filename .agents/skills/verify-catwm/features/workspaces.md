# Workspaces

The user shows another workspace, or sends the focused window to a workspace, with or without going there. The windows of a hidden workspace are parked, and they come back when the user shows that workspace again.

## Sub-features

- `ws-show` shows workspace N, the previous one, or the next one with windows.
- `ws-move` moves the focused window to workspace N and follows it.
- `ws-move-silent` moves the focused window to workspace N and stays.

## How to get to it (user POV)

- Press `Ctrl 1` to `Ctrl 0`, or `Ctrl Left` / `Ctrl Right`. Add Shift to move the focused window.
- In window mode, press `1` to `0`, and add Shift to move the window.
- Run `catwm workspace N|previous|+1|-1|e+1`, `catwm movetoworkspace N` or `catwm movetoworkspacesilent N`.

## Driving it with the catwm CLI

Preconditions:

- The baseline preconditions in the README are true. `SCRATCH_WS` and `ORIG_WS` are in the state file.
- Use `M = SCRATCH_WS + 1` as the second workspace.

- **Send silently.** Record the id of the focused test window. Run `$S/evidence.sh ws-move-silent-before`, then `$CLI movetoworkspacesilent M`. The id is in the `windows` list of workspace `.../M` in `workspaces --json`, and the screen still shows `.../SCRATCH_WS` in `status`. Run `$S/evidence.sh ws-move-silent-after`.
- **Show it.** Run `$CLI workspace M`. `status.screens[0].workspace` ends with `/M`, and the moved window is `visible: true`. The other test windows are `visible: false`.
- **Move and follow.** Run `$CLI movetoworkspace SCRATCH_WS`. The screen shows `.../SCRATCH_WS` again, and the window is back with the other test windows.
- **Previous.** Run `$CLI workspace M`, then `$CLI workspace previous`. The screen shows `.../SCRATCH_WS`.

## Gotchas

- Each workspace is a macOS Desktop, also when `status.workspaces` is `catwm`. Showing workspace N makes each missing Desktop up to N, and CatWM removes the empty ones when you leave (`native workspaces: removed Desktop ...` in the log). Use `M = SCRATCH_WS + 1`, not a high number.
- `status` can show the old workspace for some 100 ms after `workspace N`. Poll until the name ends with `/N`.
- A workspace name is `<display UUID>/<number>`. Compare only the part after `/`.
- Never send a test window to `ORIG_WS`. The user's windows are there.
- `desk.sh stop` quits the `DESK_PID` TextEdit process, so it closes the test windows on every workspace.
