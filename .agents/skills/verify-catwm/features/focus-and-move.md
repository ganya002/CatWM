# Focus and move

The user moves the focus to the window in a direction, or moves the focused window to another slot. The focus follows the moved window, and the other windows close the gap.

## Sub-features

- `focus-direction` focuses the neighbour window to the left, right, top or bottom.
- `focus-cycle` focuses the next or previous window.
- `move-direction` moves the focused window in a direction.
- `swap-master` swaps the focused window with the main window.

## How to get to it (user POV)

- In window mode, press `h j k l` or the arrow keys to move the focus, and add Shift to move the window.
- In window mode, press `Tab` or `Shift Tab` to cycle, and `m` to swap with the main window.
- Run `catwm movefocus left|right|up|down`, `catwm cyclenext [prev]`, `catwm movewindow l|r|u|d` or `catwm layoutmsg swapwithmaster`.

## Driving it with the catwm CLI

Preconditions:

- The baseline preconditions in the README are true.
- `$CLI layout tall` ran, so the slots have a known shape: one main window on the left, a stack on the right.

- **Find the focus.** Run `$CLI windows --json | jq --argjson p "$DESK_PID" '.[] | select(.pid == $p and .focused) | {id, frame}'`. Exactly one test window has the focus.
- **Focus right.** Start `$CLI events focus.changed > $RUN/focus.jsonl &` and record `$!`. Run `$CLI movefocus left`, then `$CLI movefocus right`. A `focus.changed` line arrives, and the focused window `frame.x` is larger than before.
- **Cycle.** Run `$CLI cyclenext`. Another test window has the focus.
- **Move the window.** Record the id and frame of the focused window. Run `$S/evidence.sh focus-move-before`, then `$CLI movewindow l`. The same id now has the main slot frame, and the focus is still on that id. Run `$S/evidence.sh focus-move-after`.
- **Swap with main.** Focus a stack window, then run `$CLI layoutmsg swapwithmaster`. The ids of the main slot and of that slot change places. Each test window is `OK` in `dump`.
- Kill the events pid that you recorded.

## Gotchas

- TextEdit opens without the CatWM focus. `desk.sh` runs `cyclenext` to fix that. Check the focus before the first command.
- `movefocus` to a side with no window can focus a window on the next display, or do nothing. Start from a known slot.
- The focus can move to the user's terminal if the user clicks. Check `focused` again before each step.
