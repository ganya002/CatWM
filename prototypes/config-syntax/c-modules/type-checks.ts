import { binds, embedded, options, submap } from "catwm"
// @ts-expect-error bad arg
binds([["ctrl", "h", "movefocus", "q"]])
// @ts-expect-error bad mods
binds([["ctlr", "h", "sort"]])
// @ts-expect-error focusDim off
embedded(["tiling"], options({ focusDim: { dim: true } }))
// @ts-expect-error submap needs windowMode
embedded(["tiling", "keys"], submap("x", []))
embedded(["tiling", "keys"], binds([]), options({ gaps: { size: 2 } }))
