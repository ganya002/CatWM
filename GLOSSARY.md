# Domain terms

Use [CatWM vocabulary](docs/internals/vocabulary.md) for user-facing domain terms.

- **Config text** is the old `catwm.conf` format with its assignments, comments, variable expressions, submaps, and unknown lines. `ConfigText` interprets and edits it. The migration reads it, and `ConfigDocument` uses it inside the Settings editing session.
- **Config module** is one TypeScript file in the module graph of `catwm.config.ts`. A save re-runs the changed module and the modules that import it. `ConfigEngine` owns the module registry.
- **Config override** is a value that Settings or `config.set` writes to `catwm.overrides.json`. It wins over `catwm.config.ts` until Settings drops it. `ConfigStore` owns the order: defaults, then the TypeScript config, then the overrides.
- **Embedded mode** is CatWM linked into another Mac app as a library. The host app draws the GUI, owns the permissions and turns features on through its config. Every optional feature is off until the host turns it on.
- **Tab drag** is an interaction that moves a lifted tab or a native window toward a tab group. `TabDrag` owns joining permission, hover work, and preview cleanup. `TabGroups` owns group membership.
- **Focus request** is an attempt to focus a window while macOS can still report the previous focus. `FocusRequests` owns its identity, validity, observation generations, and deferred commands. `WindowManager` performs focus effects and selects workspaces.
- **Bind interpretation** resolves a bind's modifiers, ranges and keys as one result. `BindInterpretation` owns it. Runtime installation and Settings advice use the same interpretation.
- **Native window move** moves a window to a Desktop. `NativeWindowMoves` owns creation requests, move progress, follow moves, arrival frames and membership until observation catches up. `WindowManager` performs the effects.
- **Window placement** registers restored windows and display layouts, places their frames, and holds hidden windows out of placement. Tiling owns it. Templates choose the saved setup and sequence its restore.
