# Floating and fullscreen

The user takes the focused window out of the tiling so it floats above the others, and puts it back. The user can also let the focused window fill the screen inside the tiling, and turn it off again.

## Sub-features

- `float-toggle` floats a tiled window and tiles a floating window.
- `fullscreen-toggle` makes the focused window fill the usable area, and turns it off.

## How to get to it (user POV)

- In window mode, press `v` to float or tile, and `f` for fullscreen.
- Run `catwm togglefloating` or `catwm fullscreen`.

## Driving it with the catwm CLI

Preconditions:

- The baseline preconditions in the README are true.
- `$CLI layout tall` ran. A test window has the focus.

- **Float.** Record the focused id. Run `$S/evidence.sh float-before`, then `$CLI togglefloating`. In `windows --json`, that id has `floating: true`. In `dump`, the id is in the floating list and is not a `tiled` line. The other test windows fill the space. `status.floating` is 1 larger.
- **Tile again.** Run `$CLI togglefloating`. The id is `floating: false` and `tiled ... OK` in `dump`. Run `$S/evidence.sh float-after`.
- **Fullscreen.** Run `$CLI fullscreen`. The focused window frame is the same as the screen `usable` rect in `dump` (minus the gaps). `windows --json` shows `fullscreen: true` for that id.
- **Fullscreen off.** Run `$CLI fullscreen`. The window goes back to its slot and `fullscreen: false`.

## Gotchas

- `fullscreen` is the CatWM zoom inside the tiling. `nativefullscreen` is the macOS green button. It makes a new Space. Do not use it unless the change is about native full screen.
- A floating window keeps its last frame. Check `floating`, not the frame, to prove the float.
