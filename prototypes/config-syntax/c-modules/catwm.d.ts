// PROTOTYPE for #342, candidate C. Excerpt of the shipped `catwm` module types.
import type { Dispatchers, Feature, Mod, Options, OptionsFor } from "../shared/catwm-types"

/** "", "ctrl", "ctrl shift", "$mod ctrl shift". Completes in the editor. */
export type Mods = "" | Mod | `${Mod} ${Mod}` | `${Mod} ${Mod} ${Mod}`

/**
 * One bind as a table row, the same order as a .conf `bind =` line:
 * `["ctrl shift", "1..0", "movetoworkspace", "1..10"]`.
 * The row type is a union per dispatcher, so the 4th column completes from the 3rd.
 */
export type Row = {
  [D in keyof Dispatchers]: void extends Dispatchers[D]
    ? readonly [Mods, string, D] | readonly [Mods, string, D, Exclude<Dispatchers[D], void>]
    : readonly [Mods, string, D, Dispatchers[D]]
}[keyof Dispatchers]

/** What one module adds. A module default-exports one fragment. */
export type Fragment =
  | { kind: "options"; options: Options }
  | { kind: "binds"; rows: Row[] }
  | { kind: "submap"; name: string; rows: Row[] }
  | { kind: "floating"; apps: Options["floating"] }

export function options<const O extends Options>(options: O): { kind: "options"; options: O }
export function binds(rows: Row[]): { kind: "binds"; rows: Row[] }
/** A mode entered with `[mods, key, "submap", name]`. */
export function submap(name: string, rows: Row[]): { kind: "submap"; name: string; rows: Row[] }
export function floating(apps: NonNullable<Options["floating"]>): { kind: "floating"; apps: Options["floating"] }

/** The root module: an ordered list of fragments. A later fragment overrides an earlier option. */
export function config(...fragments: Fragment[]): Fragment[]

/** Embedded mode: the root lists the features it turns on, then its fragments. */
export function embedded<const F extends Feature>(
  features: F[],
  ...fragments: EmbeddedFragment<F>[]
): Fragment[]

export type EmbeddedFragment<F extends Feature> =
  | { kind: "options"; options: OptionsFor<F> & { [K in Exclude<keyof Options, keyof OptionsFor<F>>]?: never } }
  | ("tiling" extends F ? { kind: "floating"; apps: Options["floating"] } : never)
  | ("keys" extends F ? { kind: "binds"; rows: Row[] } : never)
  | ("windowMode" extends F ? { kind: "submap"; name: string; rows: Row[] } : never)

/** The default config as fragments, to list next to your own: `config(...defaults, ./my-binds)`. */
export const defaults: Fragment[]
