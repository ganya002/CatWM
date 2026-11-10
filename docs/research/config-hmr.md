# What real HMR means for a CatWM config

Research for [#341](https://github.com/noxaur/CatWM/issues/341), part of the map [#339](https://github.com/noxaur/CatWM/issues/339). Sources were read on 2026-11-10. The WebKit source is at commit `4e28904e`, Hyprland at `9a9ca12a`, Zed at `0929d569` and Ghostty at `bd1e6a43`.

## Answer

CatWM can have real HMR, and it's simpler than web HMR, because no CatWM state lives in the JavaScript heap. Windows, workspaces, tab groups, per-screen layouts and the active submap all live in Swift (`WindowManager`, `WorkspaceModel`, `Hotkeys`). The config module graph only produces a value. So a hot swap has two parts:

1. **In JavaScript:** re-run the changed module and the modules that import it, up to the entry. Every other module keeps its instance and its module-level state. This is webpack's bubbling rule, with the config entry as the one implicit accept boundary.
2. **In Swift:** compare the new config value with the old one and apply only what changed. Today `reload()` applies everything every time.

For the engine, I recommend running a **webpack-style module registry inside one classic script**. The TypeScript transform that #340 needs anyway can also turn `import`/`export` into registry calls. Then CatWM controls which module runs again, and it only needs public JavaScriptCore API. JSC's native ES module loader is private API (SPI), and it never loads a module key twice, so each re-run needs a new URL, and the old module records are kept for the life of the context (details below).

Offer `import.meta.hot.dispose` and `import.meta.hot.data` (the Vite shape) only to modules that create side effects, such as timers or event subscriptions. A module that only exports values needs no HMR code.

## How other systems replace a module

### Vite

A module that calls `import.meta.hot.accept` is an **HMR boundary**. Vite re-runs the changed module up to the nearest boundary, and "importers up the chain from the boundary are not notified." `accept(cb)` accepts the module's own changes. `accept(deps, cb)` accepts changes to direct dependencies "without reloading itself." `dispose(cb)` cleans up "persistent side effects created by its updated copy." `prune(cb)` runs when nothing imports the module any more. `import.meta.hot.data` persists across updates of the same module path. You mutate it, and you can't reassign it. `invalidate()` forces the update up to the importers. `decline()` is now a no-op. ([Vite HMR API](https://vite.dev/guide/api-hmr))

Vite finds HMR use by static analysis: the call must appear as `import.meta.hot.accept(`, and the whitespace matters. ([Vite HMR API](https://vite.dev/guide/api-hmr))

### webpack

The webpack runtime keeps a module cache. When a module changes, "the invalid flag bubbles up and invalidates parent(s) as well. Each bubble continues until the app's entry point or a module with an update handler is reached." Modules between the change and the accepting module run again. The accepting module doesn't run again, so "its own state therefore survives the update". Unchanged modules are "reused as-is." If the change bubbles past an entry, "the update is aborted ... and the application is left running its old code." A dev server turns that into a full reload. ([webpack HMR concepts](https://webpack.js.org/concepts/hot-module-replacement/))

`module.hot.dispose(data => …)` hands state to the next copy through `module.hot.data`. The `status()` value `abort` means "the system is still in its previous state". `fail` means it "has been compromised." ([webpack HMR API](https://webpack.js.org/api/hot-module-replacement/))

### Bun

`bun --hot` doesn't restart the process: "Bun re-evaluates all files, but global state (notably, the `globalThis` object) persists." That is a whole-graph re-run that keeps globals, not module replacement. The runtime docs say "Support for Vite's `import.meta.hot` is planned." ([Bun watch mode](https://bun.com/docs/runtime/watch-mode)) Bun's full-stack dev server does support `accept`, `dispose` and `data`, "modeled after Vite's `import.meta.hot` API." It requires the full phrase `import.meta.hot.<API>` at each call. ([Bun hot reloading](https://bun.com/docs/bundler/hot-reloading))

### Window managers and terminals

None of these does module-level replacement. Each one runs the whole config again, and state survives because it lives outside the config language.

- **AwesomeWM** restarts with `execvp` on its own binary (`awesome_restart` in [awesome.c](https://github.com/awesomeWM/awesome/blob/master/awesome.c)). It keeps client state across the restart by writing it to X properties: `awful.client.property.persist` keeps `floating` by default ([lib/awful/client.lua](https://github.com/awesomeWM/awesome/blob/master/lib/awful/client.lua)). Lua code gets an `exit` signal with `reason_restart` ([awesome API](https://awesomewm.org/apidoc/core_components/awesome.html)).
- **Hammerspoon:** `hs.reload()` "reloads your init-file in a fresh Lua environment." `hs.shutdownCallback` runs before that, "e.g. serialising state," and it must not do async work ([hs docs](https://www.hammerspoon.org/docs/hs.html)).
- **Hyprland** reloads on save. Its `CConfigWatcher` uses inotify with `IN_CLOSE_WRITE` on the file. It also watches the folder for `IN_CREATE | IN_DELETE | IN_MOVED_TO | IN_MOVED_FROM`, which catches editors that save by rename. `misc:disable_autoreload` turns it off ([ConfigWatcher.cpp](https://github.com/hyprwm/Hyprland/blob/main/src/config/shared/inotify/ConfigWatcher.cpp), [ConfigValues.cpp](https://github.com/hyprwm/Hyprland/blob/main/src/config/values/ConfigValues.cpp)).
- **Zed** watches the settings file with a 100 ms debounce and sends the whole file's contents again on each event (`watch_config_file` in [settings_file.rs](https://github.com/zed-industries/zed/blob/main/crates/settings/src/settings_file.rs)).
- **Ghostty** reloads through the `reload_config` action. It notes that "not all changes can be applied at runtime" ([Binding.zig](https://github.com/ghostty-org/ghostty/blob/main/src/input/Binding.zig)). `App.updateConfig` sends the new config to every surface ([App.zig](https://github.com/ghostty-org/ghostty/blob/main/src/App.zig)). A "soft" reload sends the config again without reading the disk ([action.zig](https://github.com/ghostty-org/ghostty/blob/main/src/apprt/action.zig)). A code search of the repo found no file watcher, so I take it that reload is manual. I didn't confirm this in the docs.

The pattern: the WM's model is the state, and the config is a function that the WM applies to that state. CatWM already works this way.

## What JavaScriptCore gives you

The public macOS SDK headers (`JSContext.h`, `JSValue.h`, `JSVirtualMachine.h` …) have no module API. ES modules come from WebKit's private headers ([JSScript.h](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSScript.h), [JSContextPrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextPrivate.h)). Both are marked available from macOS 10.15:

- `+[JSScript scriptOfType:kJSScriptTypeModule withSource:andSourceURL:andBytecodeCache:inVirtualMachine:error:]`. For modules, "sourceURL … is the module identifier."
- `JSContext.moduleLoaderDelegate` with `context:fetchModuleForIdentifier:withResolveHandler:andRejectHandler:`, plus optional `willEvaluateModule:` and `didEvaluateModule:`.
- `-[JSContext evaluateJSScript:]`. A module script "will be run asynchronously and will return a promise," like a dynamic `import()`.
- `-[JSContext dependencyIdentifiersForModuleJSScript:]` returns a module's imports, so you can build the graph.

The header states the limit that matters for HMR: "Once an identifier has been resolved or rejected in a given context it will never be requested again. If a script is successfully evaluated it will not be re-evaluated on any subsequent import. The VM will retain all evaluated modules for the lifetime of the context." ([JSContextPrivate.h](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextPrivate.h)) The identifier is an absolute URL resolved against the importer. The resolve handler rejects a `JSScript` whose `sourceURL` differs from the requested key. `import.meta` holds only `url` and `filename`, so there's no `import.meta.hot`. ([JSAPIGlobalObject.mm](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSAPIGlobalObject.mm))

So HMR on the native loader would need three things:

1. **Cache busting.** Re-run a module under a new key, such as `file:///…/binds.ts?v=7`. You also have to rewrite each importer's specifier to the new key, so each importer runs again too. That matches webpack's bubbling, but the transform must do the rewrite. I haven't tested that `?v=` keys resolve as distinct modules. A prototype must confirm it.
2. **Growing memory.** Old module records stay until the context dies. Each save adds one copy of the changed chain. For a config of a few small files this is likely small, but nobody has measured it. You could recreate the `JSContext` after N swaps, which re-runs the whole graph once.
3. **SPI.** `JSScript` and `moduleLoaderDelegate` aren't in the SDK. Calling them means declaring the private interfaces yourself, and Apple can change them in any release.

A **registry inside a classic script** avoids all three. The transform wraps each module as `register("binds.ts", (require, exports, hot) => { … })`, and Swift runs it with the public `evaluateScript:withSourceURL:`. The registry keeps `exports` for each module, re-runs a changed module's function, and walks importers up to the entry. It also runs `dispose` handlers and passes `hot.data` to the next copy. This is the shape of webpack's runtime, so its semantics carry over. The cost is a small registry in JavaScript, and the loss of live ESM bindings: an importer reads the new exports only when it runs again. It runs again anyway under the bubbling rule. Which engine and transform to use is for #340 to decide. This only shows that HMR doesn't require the native loader.

**Threads.** "A virtual machine will use the run loop of the thread it was initialized on" for deferred work like garbage collection, and there's "no API to change" it. Thread safety comes from locking the VM ([JSVirtualMachine.h](https://developer.apple.com/documentation/javascriptcore/jsvirtualmachine), in the SDK). Put the VM on its own thread with a run loop, run the swap there, and post only the finished config value to the main thread. A slow or looping config then can't stall the main thread that runs `refresh()` and the `Animator` completions.

**File watching.** CatWM's own writes are atomic: `Config.write` calls `write(to:atomically: true)`, which replaces the file by rename (`Sources/CatWM/Config/Model/Config.swift`). Many editors save the same way. A `DispatchSource` vnode source on the file loses the file after the first rename. Watch the config folder instead, either with FSEvents and `kFSEventStreamCreateFlagFileEvents` or with a vnode source on the directory, and debounce the events. Zed uses 100 ms. Hyprland watches the folder for the same reason. The watcher must also see every file in the module graph, not just the entry.

## What CatWM must keep across a swap

`reload()` in `Sources/CatWM/Tiling/Manager/WindowManager+start.swift` shows what survives today. It replaces `config`, calls `surface.apply(config)` (`Sources/CatWM/App/AppSurface.swift`), sets `FocusDim` again, recomputes `autoFloating` for each window, clears `corrections`, then runs `refresh()` and emits `config.reloaded`.

**Survives today, and must keep surviving:**

- **Windows:** the `windows` map, one `Window` for each `CGWindowID`. `reload()` doesn't touch it.
- **Workspaces, order, tabs and layouts:** `WorkspaceModel` (`Sources/CatWM/Tiling/Spaces/WorkspaceModel.swift`). It holds `workspaceOf`, `order`, `monitorOf`, `shown`, `states` (each screen's layout), focus history, `tabs` and `maximisedTabs`. It's kept unless `virtualWorkspaces` flips. A change to `workspacesPerDisplay` renumbers the workspaces.
- **The active submap (key mode):** `Hotkeys.setBindings` rebuilds the bind tables but keeps `submap`. It leaves the mode only if the new config has no binds for it (`Sources/CatWM/Keys/Hotkeys/Hotkeys+setBindings.swift`). That's the right rule for HMR: saving a file while in a mode keeps you in the mode.
- **A screen's current layout** when the layout list changes: `cycleLayout` looks up the current layout in `config.layouts` and accepts a missing one (`WindowManager+context.swift`). New screens get `config.layouts.first`.

**Reset today, and HMR should reset only on a real change:**

- `nativeDesktop.stop()` runs on every reload and cuts off a Desktop slide that's in motion.
- `corrections = [:]` and `autoFloating` run for every window, even when no float rule changed.
- `surface.apply` rebuilds every bind table, and `refresh()` lays out every screen again, even when only a key bind changed.
- A `virtualWorkspaces` flip resets workspaces, labels and the overview. That reset is correct, but only when the value really changes.

An HMR swap that changes one bind should rebuild the bind tables and do nothing else. To get there, `reload()` takes the old and new `Config` and applies only the fields that differ. `Config` is a plain struct, so comparing fields is cheap. That diff is where "don't drop animation frames" is won. Evaluating JavaScript off the main thread doesn't help much if every save still triggers a `refresh()` of every screen.

**New state that HMR adds:**

- **Last good config.** If evaluation throws, keep the running config and module instances, and report the error. Use the `config.errors` path and the HUD. That's webpack's `abort` case: "still in its previous state." How to report errors is an open item on the map.
- **Side effects that config code creates.** If the TypeScript API lets config code subscribe to CatWM events, start timers or register commands, each module must release them on `dispose`. Otherwise every save adds another copy. Hammerspoon's `shutdownCallback` and Vite's `dispose` solve the same problem. CatWM can track what each module registers and release it when the module runs again, so users don't have to write `dispose` by hand.

## Open questions for a prototype

- Do `?v=N` module keys work with JSC's native loader, and how much memory does each swap keep?
- How long does a swap take on a realistic config, from save to applied bind? Measure the evaluation on its thread and the main-thread apply separately.
- Which `Config` fields can update in place, and which need the full `refresh()`?
