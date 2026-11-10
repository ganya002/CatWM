// PROTOTYPE for #342, candidate B. Excerpt of the shipped `catwm` module types.
import type { Dispatchers, Feature, KeySpec, Mod, Options, OptionsFor } from "../shared/catwm-types"

/** A finished bind. Made only by a chord's dispatcher method. */
export interface Bind { readonly __bind: unique symbol }

/** A key with its mods. Each dispatcher is a method, so `ctrl("1..0").` lists them all with docs. */
export type Chord = {
  [D in keyof Dispatchers]: void extends Dispatchers[D]
    ? (arg?: Exclude<Dispatchers[D], void>) => Bind
    : (arg: Dispatchers[D]) => Bind
}

/**
 * A mod builder: call it with keys to get a chord, or chain another mod.
 * `ctrl.shift("1..0")`, `mod.ctrl("h|j|k|l")`, `none("escape|i|return")`.
 * The keys are checked through `KeySpec`, so `ctrl("1..O")` is an error in the editor.
 */
export type ModBuilder = (<S extends string>(keys: KeySpec<S>) => Chord) & {
  readonly cmd: ModBuilder
  readonly alt: ModBuilder
  readonly ctrl: ModBuilder
  readonly shift: ModBuilder
  /** `$mod`, the mod set in the config. */
  readonly mod: ModBuilder
}

export interface Keys {
  /** No mods: for a submap. */
  none: ModBuilder
  cmd: ModBuilder
  alt: ModBuilder
  ctrl: ModBuilder
  shift: ModBuilder
  /** `$mod`, the mod set in the config. */
  mod: ModBuilder
}

export interface Config extends Options {
  /** Global binds. Work in every app. */
  binds?: (keys: Keys) => Bind[]
  /** Modes entered with `.submap(name)`. Keys with no bind are swallowed while a mode is on. */
  submaps?: Record<string, (keys: Keys) => Bind[]>
}

export function defineConfig(config: Config): Config

/**
 * Embedded mode. `features` is inferred, so options and binds of a feature
 * that is off are type errors without writing the list twice.
 */
export function defineEmbedded<const F extends Feature>(
  config: { features: F[] } & OptionsFor<F>
    & ("keys" extends F ? { binds?: (keys: Keys) => Bind[] } : {})
    & ("windowMode" extends F ? { submaps?: Record<string, (keys: Keys) => Bind[]> } : {}),
): Config

/** The default config as values, to spread and change one part: `binds: k => [...defaults.binds(k), ...]`. */
export const defaults: Required<Pick<Config, "binds" | "submaps">> & Options
