# Domain terms

Use [CatWM vocabulary](docs/internals/vocabulary.md) for user-facing domain terms.

- **Config text** is the config file with its assignments, comments, variable expressions, submaps, and unknown lines. `ConfigText` interprets and edits it. `ConfigDocument` owns the Settings editing session.
- **Tab drag** is an interaction that moves a lifted tab or a native window toward a tab group. `TabDrag` owns joining permission, hover work, and preview cleanup. `TabGroups` owns group membership.
- **Focus request** is an attempt to focus a window while macOS can still report the previous focus. `FocusRequests` owns its identity, validity, observation generations, and deferred commands. `WindowManager` performs focus effects and selects workspaces.
- **Bind interpretation** resolves a bind's modifiers, ranges and keys as one result. `BindInterpretation` owns it. Runtime installation and Settings advice use the same interpretation.
- **Native window move** moves a window to a Desktop. `NativeWindowMoves` owns creation requests, move progress, follow moves, arrival frames and membership until observation catches up. `WindowManager` performs the effects.
- **Window placement** registers restored windows and display layouts, places their frames, and holds hidden windows out of placement. Tiling owns it. Templates choose the saved setup and sequence its restore.
