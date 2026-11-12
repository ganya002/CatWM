# Dwindle layout

`dwindle` is Hyprland's default layout: each new window splits the focused window's tile along its longer side, and each split keeps its own direction and ratio. Every other CatWM layout is a pure function of the window count, so dwindle is the only one with state, `ScreenState.dwindle`.

The tree stores only structure. Its leaves are the workspace's tiled windows in `order`, matched by position. So every command that reorders windows (`swapwindow`, `movewindow`, Overview drags) swaps tiles in the tree with no dwindle-specific code. Keying leaves by window id was rejected because every reorder path would need a dwindle branch. `sync` runs before each layout: a window gone from `order` removes its leaf and its sibling takes the parent's place, and a new window splits the leaf before it. A new window is inserted into `order` right after the focused one, so it splits the focused tile. The focused window is `reportedFocus` first, because by the time the arrival is seen, the frontmost app is usually the new window's app.

A split with no explicit direction picks one from its rectangle on every layout (Hyprland without `preserve_split`). `togglesplit` fixes the direction of the focused window's parent split, `swapsplit` flips which side its first child takes, `splitratio` sets that split's ratio, and `resizeactive DX DY` moves the nearest split on each axis. Ratios stay within 0.1 to 0.9.

The tree isn't saved across restarts: a restart rebuilds it from `order` with automatic directions.
