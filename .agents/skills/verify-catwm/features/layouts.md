# Layouts

Each workspace has its own layout. The user sets a layout or steps through the `layouts` list, and the windows move to the new slots. The user can also change the size of the main pane.

## Sub-features

- `layout-set` sets a named layout on the focused display.
- `layout-cycle` steps to the next or previous layout in the `layouts` list.
- `layout-ratio` makes the main pane larger or smaller.
- `layout-retile` puts each window back in its slot.

## How to get to it (user POV)

- In window mode (default: Super + Caps Lock), press `n` or `p` to cycle the layout.
- In window mode, press `,` or `.` to change the main pane size, and `z` to retile.
- Run `catwm layout <name>`, `catwm cyclelayout next|prev`, `catwm splitratio +0.05|-0.05|exact 0.6` or `catwm retile`.

## Driving it with the catwm CLI

Preconditions:

- The baseline preconditions in the README are true.
- Record the start state: `$CLI status --json | jq -r '.screens[0].layout'` and the `ratio=` value in `$CLI dump`.

- **Set a layout.** Run `$S/evidence.sh layouts-set-before`, then `$CLI layout tall`. In `dump`, the screen line shows `layout=tall`, and each test window is `tiled ... OK`. In `windows --json`, one test window has the full height of the left part, and the others are stacked on the right.
- **Cycle.** Read the list: `grep '^layouts' "$CONF"` (`config.get` does not know `layouts`). Run `$CLI cyclelayout next`. `status.screens[0].layout` is the next name in that list. If the old layout is not in the list, CatWM goes to the first entry (seen: `tall` → `bsp` with `layouts = bsp, wide, floating, fullscreen`).
- **Ratio.** Run `$CLI layout tall`, then `$CLI splitratio exact 0.6`. In `dump`, `ratio=0.6`, and the main window width is about 60 % of `usable` minus the gaps.
- **Retile.** Run `$CLI retile`. Each test window is `OK` in `dump`.
- **Proof.** Run `$S/evidence.sh layouts-set-after`. Then put back the start layout and the ratio. The ratio belongs to the workspace and stays when you change the layout, so set it back with `splitratio exact <start ratio>`.

## Gotchas

- `layout` acts on the focused display, not on a workspace name. With more than one display, check which display has the focus.
- The `floating` and `fullscreen` layouts do not tile, so `dump` lists no `tiled` lines for them. That is correct.
- Frames animate. Read `dump` after the motion ends: poll until each line is `OK`, or wait for `tiling.changed`.
- `ratio=` can show floating-point noise (`0.7000000000000002`). Compare with a tolerance.
- `actual` can be 1 px off `target` (`849.0` for `850.0`) and still be `OK`. Read the `OK` or `MISMATCH` word, not the numbers.
