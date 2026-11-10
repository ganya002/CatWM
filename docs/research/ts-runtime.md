# How CatWM runs TypeScript within the budget

Research for [#340](https://github.com/noxaur/CatWM/issues/340), part of the map [#339](https://github.com/noxaur/CatWM/issues/339). Measured on 2026-11-10.

## Answer

Use the system JavaScriptCore through its public API (`JSContext.evaluateScript`), strip types with a bundled Sucrase build, and run modules through a small module registry that CatWM owns. This adds about 0.2 MB to the binary and measured +7.8 MB of memory with the engine and stripper kept alive. The memory stayed flat over 200 hot reloads, and a full reload of a 270-line config took 7.8 ms.

Don't use the JSC module loader (`JSScript` with `kJSScriptTypeModule` and `JSModuleLoaderDelegate`). It works, but it's private API, and its module registry never frees old modules. Re-importing under a new URL, which is the only way to re-evaluate a module, grew memory by about 100 KB a reload. After 100 saves, that's +14 MB.

Ship a `tsconfig.json` with `erasableSyntaxOnly`. Then any stripper handles user configs, Node runs them too, and a Swift stripper stays an option if the budget gets tight. A Swift stripper would cut the stripper's ~5 MB and leave the engine at about +3 MB, but I didn't build one, so that saving is an estimate.

QuickJS-ng is the measured fallback. It costs +0.7 to 0.95 MB of binary but only +0.34 MB of memory for the engine. With Sucrase loaded, it used +6.1 MB.

## Corrections to the ticket's premise

- The SDK has no `JSScript.h` and no `JSModuleLoaderDelegate`. The public headers in `MacOSX.sdk/.../JavaScriptCore.framework/Headers` stop at `JSContext.h`, `JSValue.h`, `JSVirtualMachine.h` and the C API. `JSScript.h` and `JSContextPrivate.h` are marked `Private` in WebKit's Xcode project ([JSScript.h](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSScript.h), [JSContextPrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextPrivate.h)).
- These APIs date from macOS 10.15, not 14. `JSContextPrivate.h` marks `moduleLoaderDelegate`, `evaluateJSScript:` and `dependencyIdentifiersForModuleJSScript:` with `JSC_API_AVAILABLE(macos(10.15), ios(13.0))`.
- The classes do exist at runtime. On macOS 27.0.1, `NSClassFromString(@"JSScript")` returns a class that answers `scriptOfType:withSource:andSourceURL:andBytecodeCache:inVirtualMachine:error:`, and `JSContext` answers `setModuleLoaderDelegate:` and `evaluateJSScript:`.
- In a public `JSContext`, `import()` does nothing useful without the delegate, and `import.meta` throws `SyntaxError: import.meta is only valid inside modules.`

## Measurements

### Setup

All numbers come from throwaway Objective-C and C harnesses on an arm64 Mac, macOS 27.0.1, Apple clang from Swift 6.4.2, `-O2`. Memory is `phys_footprint` from `task_info(TASK_VM_INFO)`, the number Activity Monitor shows. Each value is the delta from the harness's own baseline before the engine starts. The harness is a bare CLI process, not CatWM, so these are engine costs, not a CatWM release-build measurement. Each row is the median of three runs unless noted.

The fixture is a 270-line `config.ts` with interfaces, generics, `as const`, `satisfies`, type-only imports and a relative import of `helpers.ts`. It uses only erasable syntax. It exports a function that returns a config object.

JavaScriptCore costs no binary size: CatWM doesn't link it today, but the running release CatWM already has `JavaScriptCore.framework` mapped from the shared cache (`vmmap` on the live process). Linking it adds only the import.

### Stripper bundles

Each stripper was bundled with `bun build --minify --format=iife --target=browser` into one script that sets `globalThis.strip`.

| Stripper | Version | Bundle | gzip | Notes |
|---|---|---|---|---|
| Sucrase | 3.35.1 | 209 KB | 47 KB | Own parser, about 8.5k lines of JS. |
| ts-blank-space | 0.9.0 | 3.65 MB | 1.03 MB | Bundles the TypeScript 6.0.3 compiler for its parser. Its `package.json` pins `typescript` to `5.1.6 - 6.0.x`, and the TypeScript 7 package is now a Go binary. |
| SWC (`@swc/wasm-typescript`, `strip-only`) | 1.16.22 | 4.08 MB | 1.50 MB | WASM inlined in JS. Needs `TextEncoder` and `TextDecoder`, which `JSContext` doesn't have. I added a 2 KB polyfill. |
| oxc-transform WASM | 0.158.0 | 3.4 MB `.wasm` | not measured | Over budget before glue. Not run. |
| esbuild-wasm | 0.28.2 | 14.0 MB `.wasm` | not measured | Over budget. Not run. |

`WebAssembly` is available in a plain `JSContext`: `new WebAssembly.Module(...)` works.

### JavaScriptCore, one cold run

Columns: create the context, load the stripper bundle, then strip and run the config through the private module loader. Memory is after the run, after `JSGarbageCollect`, and after releasing the context and VM.

| Path | Context | Load stripper | Strip + run | Total | Memory kept alive | After teardown |
|---|---|---|---|---|---|---|
| No stripper (pre-stripped JS) | 1.5 to 4.6 ms | — | 0.8 to 2.0 ms | 2.3 to 6.6 ms | +3.1 MB | +3.1 MB |
| Sucrase | 1.9 to 4.2 ms | 7.6 to 13.3 ms | 13.2 to 17.7 ms | 22.7 to 35.2 ms | +8.6 MB | +8.3 MB, +7.3 MB after 5 s |
| ts-blank-space | 3.1 to 4.6 ms | 82 to 92 ms | 12 to 13 ms | 98 to 109 ms | +36.1 MB | +34.1 MB, +23.9 MB after 5 s |
| SWC WASM | 4.3 to 5.6 ms | 455 to 458 ms | 9.6 to 10.4 ms | 469 to 474 ms | +35.0 MB | +29.0 MB |

The first-ever context in a fresh boot of the harness took 29 ms. Later runs took 2 to 5 ms, so expect a one-time page-in cost at CatWM launch.

Tearing the engine down doesn't give the memory back to the system. `malloc_zone_pressure_relief` changed little, and JSC's scavenger returned part of it after about 5 s. But the memory is reused: creating a fresh `JSContext` for each of 200 reloads stayed flat at +4.0 MB, at 0.5 ms a reload. So "load the engine only when the config changes" saves nothing after the first load. Budget for the engine kept alive.

Only Sucrase fits the +10 MB budget. ts-blank-space and SWC each use over 3 times the budget.

### Hot reload in JavaScriptCore

Each test re-evaluates the whole config graph (`config.ts` and `helpers.ts`) once per reload, with a GC every 25 reloads.

| Module system | Stripper | Memory after 25 / 50 / 100 / 200 reloads | Time per reload |
|---|---|---|---|
| Private JSC loader, new `?v=N` URL each reload | none | +6.8 / +8.9 / +14.0 MB / not run | 0.3 ms |
| Private JSC loader, new `?v=N` URL each reload | Sucrase | +9.6 / +11.0 / +14.3 MB / not run | 8.2 ms |
| Fresh `JSContext` each reload (full re-run) | none | +3.7 / +3.9 / +3.9 / +4.0 MB | 0.5 ms |
| CatWM registry: Sucrase `imports` transform, `Map` of modules, delete to invalidate | Sucrase | +8.7 / +8.6 / +7.9 / +7.8 MB | 7.8 ms |

The JSC loader caches each module by its resolved URL. Importing the same URL again returns the old module without fetching it. A relative `import './lib.js'` inside a re-imported `main.js?t=2` still resolves to the cached `lib.js`. To re-evaluate a module, you have to give it a new URL and rewrite the import specifiers of every module that imports it. That's what Vite does in the browser, but the registry keeps every version.

The CatWM registry needs no private API. Sucrase's `imports` transform turns `import` and `export` into `require` calls and `exports` assignments. CatWM wraps each module in `function(exports, require, module)` and evaluates it with `evaluateScript(_:withSourceURL:)`, so stack traces keep the file name. Real HMR re-runs only the changed module and the modules that import it, up to a module that accepts the update. Deleting the old entries from the `Map` lets them be collected, which is why memory stays flat. One semantic difference: CommonJS-style exports aren't live bindings, so a module that reassigns an exported `let` won't update its importers. That doesn't matter for a config.

### QuickJS-ng

Built from [quickjs-ng](https://github.com/quickjs-ng/quickjs) at commit `71e6367` (0.18.0): `quickjs.c`, `libregexp.c`, `libunicode.c`, `dtoa.c`, without `quickjs-libc`, linked with `-flto -Wl,-dead_strip` and stripped.

| | Result |
|---|---|
| Binary cost | +0.95 MB at `-O2`, +0.68 MB at `-Os` (minus a 33 KB empty program) |
| Engine + pre-stripped config, kept alive | +0.34 MB |
| Cold run (runtime, context, module load, run) | 0.4 ms warm, 2.4 ms first run |
| Fresh runtime per reload, 200 reloads | 0.24 to 0.38 ms each, +2.2 MB after |
| Sucrase loaded, kept alive | +6.1 MB. Load 14.7 ms, first strip 13.0 ms, warm strip 10.9 ms |
| ts-blank-space loaded, kept alive | +43.3 MB. Load 169 ms |

QuickJS has a public ES module API (`JS_SetModuleLoaderFunc`, `JS_EVAL_TYPE_MODULE`). It has no API to unload one module, so a module reload means a fresh runtime or the same registry trick as JSC. It's an interpreter with no JIT, which is fine for a config but slower for event handlers that run often. Not measured: handler throughput.

Other engines aren't worth measuring for this budget. V8 and SpiderMonkey are tens of MB. Hermes needs ahead-of-time bytecode compilation for good startup, which conflicts with editing a source file.

## Type-stripping paths

| Path | Binary | Memory (with JSC) | Cold run | TS syntax | ES modules and HMR |
|---|---|---|---|---|---|
| Sucrase, bundled JS | +0.21 MB | +8.6 MB measured | 23 to 35 ms | `enum` and parameter properties work (tested). A `namespace` with values was silently dropped from the output (tested). Decorators pass through untransformed, and `const enum` isn't inlined across files ([Sucrase README](https://github.com/alangpierce/sucrase#transforms)). | Strips types and can also turn ESM into CommonJS, which is what makes a freeable module registry possible. |
| ts-blank-space, bundled JS | +3.65 MB | +36 MB measured | 94 to 109 ms | Erasable syntax only. Reports `enum`, `namespace` and `module` with values, parameter properties, `import =`, `export =` and legacy decorators as errors ([unsupported_syntax.md](https://github.com/bloomberg/ts-blank-space/blob/main/docs/unsupported_syntax.md)). Keeps line and column positions, so no source map is needed. | Strips only. Needs the JSC loader or another transform for modules. |
| SWC WASM (`@swc/wasm-typescript`) | +4.08 MB | +35 MB measured | 469 ms | `strip-only` mode: erasable syntax. `transform` mode: `enum` and namespaces too. This is what Node's `amaro` wraps ([Node TypeScript docs](https://nodejs.org/api/typescript.html)). | Strips only. |
| Stripper in Swift | Not measured. Likely tens of KB of code. | Not measured. Engine only: +3.1 MB measured. | Not measured | Erasable syntax only, as far as the parser you write handles it. | Swift could also do the ESM-to-registry rewrite. |
| Erasable-syntax-only TypeScript | 0 | 0 | 0 | The rule, not a tool. TypeScript 5.8's `--erasableSyntaxOnly` makes `tsc` reject `enum`, namespaces and modules with runtime code, parameter properties, and `import =` and `export =` ([TS 5.8 notes](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-8.html#the---erasablesyntaxonly-option)). Node strips the same subset by default. | Needs one of the strippers above. The editor enforces it, CatWM doesn't. |

A Swift stripper is the only path that could cut memory to about +3 MB. Writing one is real work. It needs a TypeScript-aware tokenizer that tells types from expressions. Two examples: `a < b > (c)` (generic call or two comparisons) and arrow functions with return types. Sucrase's parser is 8.5k lines for comparison. Only build it if CatWM's other features need the ~5 MB Sucrase uses.

## How I'd use this

- Engine: system JavaScriptCore, public API only. 0 MB binary, Safari Web Inspector debugging through `JSContext.isInspectable` (public since macOS 13.3), and Apple ships its security fixes.
- Stripper: Sucrase with the `typescript` and `imports` transforms, bundled as one 209 KB resource.
- Modules and HMR: a CatWM-owned registry (`Map` from path to module record) with per-module invalidation and an `import.meta.hot`-style accept. Sucrase's `imports` transform leaves `import.meta` as is (tested), and `import.meta` is a syntax error outside a module, so CatWM has to rewrite it, for example `import.meta.hot` to a parameter of the module wrapper. How the HMR API looks to the user is for the HMR ticket.
- Syntax: ship `tsconfig.json` with `erasableSyntaxOnly: true` and `verbatimModuleSyntax: true`, so configs stay portable to a Swift stripper and to Node.

## What wasn't measured

- Memory and launch time inside a release CatWM build. The deltas above are from bare CLI harnesses.
- A Swift stripper. No prototype was written.
- Sucrase in JSC with a bytecode cache. The cache is only reachable through private `JSScript`.
- Event handler throughput in QuickJS compared with JSC.
- Configs much larger than 270 lines, and the effect of a large `.d.ts` on the editor. The `.d.ts` doesn't load at runtime.

## Reproduce

Bundle each stripper with `bun build entry.js --minify --format=iife --target=browser`, where the entry sets `globalThis.strip`. Then run a harness that creates a `JSContext`, evaluates the bundle, sets a `JSModuleLoaderDelegate` (declare the private interfaces from WebKit's `JSScript.h` and `JSContextPrivate.h`), `import()`s the config, and prints `phys_footprint` at each step. The QuickJS harness does the same through `JS_SetModuleLoaderFunc`. The harnesses were throwaway and aren't committed.
