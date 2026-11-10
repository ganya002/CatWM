// PROTOTYPE for #342, candidate A in embedded mode.
// A host app links CatWM. Every optional feature is off; this config turns on
// tiling, tab strips and keys. `focusDim: {...}` here would be a type error,
// because `focusDim` is not in `features`.

import type { EmbeddedConfig } from "catwm"

export default {
  features: ["tiling", "tabStrips", "keys"],

  layouts: ["bsp", "tall"],
  gaps: { size: 8 },
  padding: 8,
  tabs: { autoHideStrip: true },

  mod: "alt",
  binds: {
    "$mod ctrl h|j|k|l": ["movefocus", "l|d|u|r"],
    "$mod ctrl shift h|j|k|l": ["movewindow", "l|d|u|r"],
    "$mod ctrl cmd h|j|k|l": ["moveintogroup", "l|d|u|r"],
    "$mod ctrl bracketleft|bracketright": ["changegroupactive", "b|f"],
    "$mod ctrl v": "togglefloating",
  },
} satisfies EmbeddedConfig<"tiling" | "tabStrips" | "keys"> // the list is written twice: an object cannot infer it
