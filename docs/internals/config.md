# Config: TypeScript, the `catwm` module and overrides

`ConfigStore` (`Config/Script/`) owns the config that CatWM runs. It reads `catwm.config.ts` from `Instance.configFolder`, then `catwm.overrides.json`, and gives `WindowManager` one `Config`.

## Parts (`Sources/CatWMKit/Config/Script/`)

- `ConfigEngine`: the system JavaScriptCore through its public API, on its own thread with a run loop. It loads the bundled `sucrase.js` (Sucrase 3.35.1, `Tools/bundle-sucrase.sh`) once and keeps the context loaded. Only the finished value goes to the main thread.
- `ConfigRuntime`: the module registry in JavaScript. Sucrase turns `import` and `export` into `require` and `exports`, and each module runs as `function (exports, require, module)`. Every save runs the entry again from a fresh module map and keeps only the compiled functions, by file text, so Sucrase doesn't run twice on an unchanged file. A failed run, or a value that `ConfigScript` rejects, keeps the last good config and the key functions that went with it. CatWM doesn't use the native ES module loader: it's private API and keeps each old module for the life of the context.
- `ConfigCatwm`: the host module that `import { catwm } from "./catwm"` resolves to. See "The `catwm` module".
- `ConfigScript`: reads the store into `Config`. Each option's path comes from `.script(...)` in the option table. Only the paths in the value change, so reading the TypeScript value and then the overrides gives the precedence. `ConfigScript+rules` reads the recorded window and workspace rules into `Config.windowRules` and `Config.workspaceRules`.
- `ConfigWatcher`: FSEvents on the config folder and the folders of the imported files, not on the files. Editors and CatWM save by rename.
- `ConfigMigration`: turns `catwm.conf` text into TypeScript with `Config.parse` and `BindRange`. `ConfigStore` writes the result only when it runs and gives the same `Config`, never over an existing `catwm.config.ts`, and once (`DefaultsKey.migratedConfigToTypeScript`). A failed conversion leaves `catwm.conf` in use and reports why.
- `ConfigTypes`: `catwm.d.ts` and `tsconfig.json`. The `catwm` object's types come from the option table, so a new option needs no second list. CatWM writes the types each launch, and `./build.sh` writes the same file to `Resources/AgentDocs/catwm.d.ts`.

## The `catwm` module

A config sets options as `catwm.gaps.size = 10` instead of exporting one object. We chose that over `export default` for three reasons. Every default is readable (`catwm.gaps.size + 2`), so a config can build on what it has. A small config is a few lines, not an object that repeats the structure. And a file that imports `catwm` can set options itself, so a helper module needs no return value to merge.

- **One store, merged on write.** An object assignment merges recursively, a list or scalar replaces, and `undefined` resets to the default. A list is a real array with `remove(value)` added. We rejected `clear()`: assigning `[]` does the same.
- **Writes happen while the config loads.** A write from a promise, or after the run, can't reach the result, so it is a `validate` error instead of a silent loss. `ConfigEngine.run` collects those late writes after the run.
- **No `export default`.** A default export can't be merged with the store, so it is an error that shows the conversion.
- **A full re-run on every save.** The earlier design re-ran only the changed modules and the modules that import them, which needed an import graph and a cache to invalidate. With one shared store a module's writes are part of the result, so a save that changes one file would have to replay the writes of the others. Running everything again costs a few milliseconds for a config of this size (the log line `config: ran N modules in X ms` shows it) and removes that state.
- **Scoped options.** An entry in the option table can be `.scoped()`: a workspace could set it without changing anything else. The generated types, the validation of workspace rules and the `catwm.d.ts` scoped list all come from that flag.
- **Motion styles** live in one list (`MotionStyle.all`). Settings → Motion and the `catwm` module read the same list, and `catwm.motion.style = "snappy"` expands to its field values at write time, so Swift never sees `style`.

### Rules

`catwm.windows(match, win => …)` and `catwm.workspaces(match, () => …)` run their function once while the config loads, in a recording mode. A window rule records actions, such as `setfloating` and `resizeactive exact 600 500`, as the same dispatchers a key runs. A workspace rule records the scoped options its function wrote. `ConfigScript` reads both into data on `Config` (`Condition`, `WindowRule`, `WorkspaceRule`), and a RegExp becomes an `NSRegularExpression`, or a diagnostic if it can't convert. Rules are data so that the window manager can evaluate them on its own thread without running JavaScript, and so that `Config.changes` can compare them.

`WindowManager+rules` applies window rules. `refresh()` calls it for each window that appeared or changed title since the last pass, so no work happens per refresh otherwise. Each window keeps the set of rule indexes that matched last time (`Window.matchedRules`), and a rule's actions run when its index enters the set. We rejected re-applying on every refresh: it would snap a window back after the user moved it. The actions run through the same `WindowAction`s as a key, with `ActionContext.target` set to the window, so a rule moves its own window and never the focused one. Rules run in file order, so the later of two matching rules wins. The facts are the window's bundle ID, title, pid, workspace, display, floating, minimized and fullscreen state. `role` is always the standard window subrole, because the scanner admits only standard windows.

### Workspace rules in `refresh()`

`refresh()` resolves each visible workspace's config (`Config.resolved(for:)`, `WindowManager+workspaceRules`) right after the workspace reconciliation and before the layout asks for slots: the base config (which already holds the Settings overrides), then each matching rule in file order, last write wins per field. A rule beats a Settings override because the override only changes the base the rule starts from.

- **Resolve before layout, so no second pass.** The facts (window count, windows per app, apps, layout, name, display, focus) don't depend on the slots, so a rule that changes gaps or padding is already in effect when the slots are computed, in the same refresh. A rule can't change a fact it matches on, so nothing can loop.
- **No cache across refreshes.** A fact is a count over `visible`, the windows CatWM places on the shown Desktop (tiled or floating; minimised windows and windows of hidden apps aren't there). That costs microseconds for a few rules, and a cache would have to be invalidated by every window event. Without rules `refresh()` does one empty-list check.
- **New windows are ordered after the resolve.** `newWindowsToMain` is scoped, and a window's workspace is only known after reconciliation, so `placeArrivals` no longer inserts arrivals into `order`. `orderArrivals` does it once the config is resolved.

Everything that places a window reads the resolved config of that window's workspace (`config(on:)`, `motion(of:)`). Readers that aren't tied to a workspace (panels, the tab strip's own fades) keep the base config.

### Floating: the latest change wins

Floating has three sources: `floating.apps` (through `Window.autoFloating`), a rule's `setfloating` or `settiled`, and the user's toggle. We rejected a fixed ranking. A user who tiles one Calculator window wants it to stay tiled, and a user who lists an app after tiling its windows wants them to float. Each source writes `Window.userFloating` when it fires, and `isFloating` reads that, so the last write wins and no source needs to know about the others. A save fires only for windows whose result changed. `applyFloatingChanges` compares the result before and after the save (the last matching rule's float or tile, else the list) and writes `userFloating` for a window that differs, or clears it to `.automatic` when no rule decides it. A save that changes nothing for a window leaves its toggle alone, so a save never undoes the user's toggle by itself.

### Key functions

`catwm.bind(mods, key, () => …)` keeps the function in a table on the config thread and writes a reference (`{function: N}`) into the bind. The table is replaced only after a run succeeds. Pressing the key calls `ConfigEngine.call(function:window:)` with a snapshot of the focused window. The call runs off the main thread and main never waits on it: `ConfigStore.call` hands the request to the engine thread and returns, and the result comes back on main as the recorded actions. `WindowManager.run(_ binding:)` runs each through `dispatch`, as if the user pressed separate binds. The hotkey handler of both surfaces calls it, so the app and embedded mode share one path. Actions still run if a save replaced the config in between, because the actions are plain data and a guard would drop a key the user did press. A throw or a timeout runs no actions and reports like a config error.

## Applying a change

`WindowManager.apply` compares the new `Config` with the old one (`Config.changes`) and applies only what differs. A bind change calls `surface.apply` and lays out nothing. A Desktop slide stops only when `virtual-workspaces` or `workspaces-per-display` changes. `refresh()` runs only for a field outside `WindowManager.liveFields`. An unchanged config with the same diagnostics does nothing, so the watcher event after an overrides write is free.

## Errors

A failure is a `ConfigDiagnostic`: file, line, phase (`read`, `resolve`, `transform`, `evaluate`, `validate`, `migrate`) and message. `ConfigStore.failures` holds the last failure until a good save. A script that runs longer than `ConfigEngine.timeLimit` (1 s of CPU time), such as an endless loop, counts as a failure. The private `JSContextGroupSetExecutionTimeLimit` stops it, usually within about 2.5 s of wall time. The engine then rolls its module registry back and keeps the last good config, and the next save runs on the same thread. A run that still hasn't returned after `ConfigStore.timeLimit` (5 s), for example in a native call, makes CatWM stop waiting and start a new engine. That old thread keeps running until CatWM quits. The menu bar menu shows it, and `config.reloaded` sends every diagnostic in `errors`.

## Settings

Settings and `config.set` never write the TypeScript file. `ConfigDocument` edits `ConfigStore.settingsText` and reloads it after each save of the TypeScript config. A Settings save takes only what changed from the text it loaded, puts it on the running config, and writes the values that differ from the TypeScript config (`ConfigStore.base`) as overrides. So a value that the `.conf` text can't hold, such as a command with a line break, keeps its TypeScript value. Settings → General lists the overrides and drops one with **Use File Value**. Saved presets in `configs.json` keep their `.conf` text and apply through the same path.

## Embedded mode

`ConfigStore(embedded: true)` starts from `Config.embedded`, with every feature off, and reads the entry file that the host gives (`use(entry:)`). It writes no files: no migration, no default config, no `catwm.d.ts`, and it keeps the overrides in memory. `ConfigScript.read(embedded: true)` rejects the features that embedded mode doesn't have. See `docs/internals/embedding.md`.
