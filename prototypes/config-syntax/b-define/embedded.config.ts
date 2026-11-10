// PROTOTYPE for #342, candidate B in embedded mode.
// A host app links CatWM. Every optional feature is off; this config turns on
// tiling, tab strips and keys. `features` is inferred, so `focusDim: {...}` or a
// `submaps` field here is a type error until "focusDim" or "windowMode" is listed.

import { defineEmbedded } from "catwm"

export default defineEmbedded({
  features: ["tiling", "tabStrips", "keys"],

  layouts: ["bsp", "tall"],
  gaps: { size: 8 },
  padding: 8,
  tabs: { autoHideStrip: true },

  mod: "alt",
  binds: ({ mod }) => [
    mod.ctrl("h|j|k|l").movefocus("l|d|u|r"),
    mod.ctrl.shift("h|j|k|l").movewindow("l|d|u|r"),
    mod.ctrl.cmd("h|j|k|l").moveintogroup("l|d|u|r"),
    mod.ctrl("bracketleft|bracketright").changegroupactive("b|f"),
    mod.ctrl("v").togglefloating(),
  ],
})
