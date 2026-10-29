# Domain terms

Use [CatWM vocabulary](docs/internals/vocabulary.md) for user-facing domain terms.

- **Config text** is the config file with its assignments, comments, variable expressions, submaps, and unknown lines. `ConfigText` interprets and edits it. `ConfigDocument` owns the Settings editing session.
- **Tab drag** is an interaction that moves a lifted tab or a native window toward a tab group. `TabDrag` owns joining permission, hover work, and preview cleanup. `TabGroups` owns group membership.
- **Focus request** is an attempt to focus a window while macOS can still report the previous focus. `FocusRequests` owns its identity, validity, observation generations, and deferred commands. `WindowManager` performs focus effects and selects workspaces.
