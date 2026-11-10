// PROTOTYPE for #342, candidate A. Excerpt of the shipped `catwm` module types.
import type { Action, Feature, Options, OptionsFor } from "../shared/catwm-types"

/**
 * Chord → action. The chord is mods and a key separated by spaces, in any order:
 * `"$mod shift tab"`, `"ctrl 1..0"`, `"h|j|k|l"` (no mods, for a submap).
 * A key list or range pairs with a `|` list or range in the args.
 */
export type Binds = Record<string, Action>

export interface Config extends Options {
  /** Global binds. Work in every app. */
  binds?: Binds
  /** Modes entered with `["submap", name]`. Keys with no bind are swallowed while a mode is on. */
  submaps?: Record<string, Binds>
}

/** Embedded mode: only the listed features run, and only their options type-check. */
export type EmbeddedConfig<F extends Feature> = OptionsFor<F> & {
  features: F[]
} & ("keys" extends F ? { binds?: Binds } : {})
  & ("windowMode" extends F ? { submaps?: Record<string, Binds> } : {})

// The user writes `export default { ... } satisfies Config`.
// Because the chord is an object key, the editor completes the action but not the chord:
// a typo such as "ctlr 1..0" is caught when CatWM loads the file, not while typing.
