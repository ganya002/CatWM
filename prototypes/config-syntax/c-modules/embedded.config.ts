// PROTOTYPE for #342, candidate C in embedded mode.
// A host app links CatWM. Every optional feature is off; the root names the features it
// turns on, then lists fragments. A `submap(...)` or `options({ focusDim })` fragment is a
// type error until "windowMode" or "focusDim" is listed. A host can ship its fragments in
// its bundle and let the user add their own module next to them.

import { binds, embedded, options } from "catwm"

export default embedded(
  ["tiling", "tabStrips", "keys"],

  options({
    layouts: ["bsp", "tall"],
    gaps: { size: 8 },
    padding: 8,
    tabs: { autoHideStrip: true },
    mod: "alt",
  }),

  binds([
    ["$mod ctrl", "h|j|k|l", "movefocus", "l|d|u|r"],
    ["$mod ctrl shift", "h|j|k|l", "movewindow", "l|d|u|r"],
    ["$mod ctrl cmd", "h|j|k|l", "moveintogroup", "l|d|u|r"],
    ["$mod ctrl", "bracketleft|bracketright", "changegroupactive", "b|f"],
    ["$mod ctrl", "v", "togglefloating"],
  ]),
)
