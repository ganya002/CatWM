import { defineConfig, defineEmbedded } from "catwm"
defineConfig({ binds: ({ ctrl }) => [
  // @ts-expect-error bad key
  ctrl("1..O").workspace(1),
  // @ts-expect-error bad arg
  ctrl("h").movefocus("q"),
  // @ts-expect-error unknown dispatcher
  ctrl("h").sortt(),
] })
// @ts-expect-error focusDim off
defineEmbedded({ features: ["tiling"], focusDim: { dim: true } })
// @ts-expect-error binds need keys
defineEmbedded({ features: ["tiling"], binds: () => [] })
