# Prototype: config syntax for a TypeScript CatWM config (#342)

This is throwaway code for one question: what should a typed CatWM config look like in TypeScript? Each candidate ports the stock config: every option in `Options.all` except the two diagnostics flags, the global binds, the `window` submap and the floating apps. Each also has a short embedded-mode config that turns on only tiling, tab strips and keys. Nothing here runs, but you can type-check every file.

All three use the same option names (`shared/catwm-types.d.ts`). The options are grouped like the Settings pages, and each field names the `.conf` key it replaces. So you compare only how each candidate builds a config, not what it calls things.

| | A: object | B: define and builders | C: modules |
|---|---|---|---|
| Entry | `export default {…} satisfies Config` | `export default defineConfig({…})` | `export default config(options, …)` |
| A bind | `"ctrl 1..0": ["workspace", "1..10"]` | `ctrl("1..0").workspace("1..10")` | `["ctrl", "1..0", "workspace", "1..10"]` |
| Editor checks the key | no, CatWM checks on load | yes | no, CatWM checks on load |
| Editor checks the mods | no | yes | yes |
| Embedded feature list | written twice | inferred | inferred |
| HMR unit | one module, value diff | one module, value diff per bind function | one module per fragment |
| Settings can write it | yes, it's data | only the options | yes, `options.ts` is data |

## Files

- `a-object/`: one default-exported object. Binds map a chord string to an action.
- `b-define/`: `defineConfig` with chord builders. Each dispatcher is a typed method, so `mod("o").` lists them all.
- `c-modules/`: a root that lists modules. Each module returns one fragment: options, floating apps, global binds or a submap. Binds are table rows in `.conf` order.
- `shared/catwm-types.d.ts`: options, keys, dispatchers and the proposed embedded features.

Each folder has its `catwm.d.ts` excerpt, `catwm.config.ts`, `embedded.config.ts` and `type-checks.ts`. The last one holds `@ts-expect-error` cases, such as an unknown dispatcher, a bad argument and a disabled feature's option.

## Check the types

```sh
cd prototypes/config-syntax/b-define && tsc -p .
```

All three folders pass with TypeScript 7.0.2 in strict mode. A typo gets the usual hint, for example `Type '"ease-outt"' is not assignable to type 'AnimationCurve'. Did you mean '"ease-out"'?`.

## What is not settled here

- The embedded `Feature` list is a proposal. #345 decides it. Its names come from existing parts of CatWM; it adds no new feature.
- HMR notes assume CatWM evaluates the config module itself and diffs the result. #341 decides what real HMR means.
- What a module may contain (C) is #347. The `.conf` migration is #348.
