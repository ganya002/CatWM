import type { Config, EmbeddedConfig } from "catwm"
// @ts-expect-error unknown dispatcher
const a = { binds: { "x": "sortt" } } satisfies Config
// @ts-expect-error bad arg
const b = { binds: { "x": ["movefocus", "q"] } } satisfies Config
// @ts-expect-error focusDim off
const c = { features: ["tiling"], focusDim: { dim: true } } satisfies EmbeddedConfig<"tiling">
// @ts-expect-error binds need keys
const d = { features: ["tiling"], binds: {} } satisfies EmbeddedConfig<"tiling">
