# Config: TypeScript, HMR and overrides

`ConfigStore` (`Config/Script/`) owns the config that CatWM runs. It reads `catwm.config.ts` from `Instance.configFolder`, then `catwm.overrides.json`, and gives `WindowManager` one `Config`.

## Parts (`Sources/CatWMKit/Config/Script/`)

- `ConfigEngine`: the system JavaScriptCore through its public API, on its own thread with a run loop. It loads the bundled `sucrase.js` (Sucrase 3.35.1, `Tools/bundle-sucrase.sh`) once and keeps the context loaded. Only the finished value goes to the main thread.
- `ConfigRuntime`: the module registry in JavaScript. Sucrase turns `import` and `export` into `require` and `exports`, and each module runs as `function (exports, require, module)`. A run with changed files deletes them and every module that imports them, then runs the entry again. Every other module keeps its exports. A failed run, or a value that `ConfigScript` rejects, puts the last good registry back. CatWM doesn't use the native ES module loader: it's private API and keeps each old module for the life of the context.
- `ConfigScript`: reads the value into `Config`. Each option's path comes from `.script(...)` in the option table. Only the paths in the value change, so reading the TypeScript value and then the overrides gives the precedence.
- `ConfigWatcher`: FSEvents on the config folder and the folders of the imported files, not on the files. Editors and CatWM save by rename.
- `ConfigMigration`: turns `catwm.conf` text into TypeScript with `Config.parse` and `BindRange`. `ConfigStore` writes the result only when it runs and gives the same `Config`, never over an existing `catwm.config.ts`, and once (`DefaultsKey.migratedConfigToTypeScript`). A failed conversion leaves `catwm.conf` in use and reports why.
- `ConfigTypes`: `catwm.d.ts` and `tsconfig.json`. CatWM writes the types each launch, and `./build.sh` writes the same file to `Resources/AgentDocs/catwm.d.ts`.

## Applying a change

`WindowManager.apply` compares the new `Config` with the old one (`Config.changes`) and applies only what differs. A bind change calls `surface.apply` and lays out nothing. A Desktop slide stops only when `virtual-workspaces` or `workspaces-per-display` changes. `refresh()` runs only for a field outside `WindowManager.liveFields`. An unchanged config with the same diagnostics does nothing, so the watcher event after an overrides write is free.

## Errors

A failure is a `ConfigDiagnostic`: file, line, phase (`read`, `resolve`, `transform`, `evaluate`, `validate`, `migrate`) and message. `ConfigStore.failures` holds the last failure until a good save. A script that runs longer than `ConfigEngine.timeLimit` (1 s of CPU time), such as an endless loop, counts as a failure. The private `JSContextGroupSetExecutionTimeLimit` stops it, usually within about 2.5 s of wall time. The engine then rolls its module registry back and keeps the last good config, and the next save runs on the same thread. A run that still hasn't returned after `ConfigStore.timeLimit` (5 s), for example in a native call, makes CatWM stop waiting and start a new engine. That old thread keeps running until CatWM quits. The menu bar menu shows it, and `config.reloaded` sends every diagnostic in `errors`.

## Settings

Settings and `config.set` never write the TypeScript file. `ConfigDocument` edits `ConfigStore.settingsText` and reloads it after each save of the TypeScript config. A Settings save takes only what changed from the text it loaded, puts it on the running config, and writes the values that differ from the TypeScript config (`ConfigStore.base`) as overrides. So a value that the `.conf` text can't hold, such as a command with a line break, keeps its TypeScript value. Settings → General lists the overrides and drops one with **Use File Value**. Saved presets in `configs.json` keep their `.conf` text and apply through the same path.

## Embedded mode

`ConfigStore(embedded: true)` starts from `Config.embedded`, with every feature off, and reads the entry file that the host gives (`use(entry:)`). It writes no files: no migration, no default config, no `catwm.d.ts`, and it keeps the overrides in memory. `ConfigScript.read(embedded: true)` rejects the features that embedded mode doesn't have. See `docs/internals/embedding.md`.
