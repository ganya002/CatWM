# Add a setting

1. Add a property to `Config`.
2. Add one option declaration with `.setting(...)` in `Config/Options/Options.swift`. Set its section, order, range, and enabled state there. Effect descriptors can publish their options beside the effect.
3. Give it `.script("group.name")`, its path in `catwm.config.ts`. Pass `type:` when the TypeScript type is narrower than the value kind. `ConfigScript` reads the path, and `ConfigTypes` writes it to `catwm.d.ts`.
4. If a change to the option must lay out the windows again, do nothing. If it applies without a new layout, add its key to `WindowManager.liveFields`.
5. Run `./build.sh --dev`. It generates `Resources/AgentDocs/config.md` and `Resources/AgentDocs/catwm.d.ts` from the option declarations.

`OptionRows` renders the declaration. Settings search reads the same declaration. Keep custom controls in that renderer. Put pointer behavior in `PointerActions` or its effect descriptor. The build collects custom search entries and palette tokens. Dispatcher names come from `WindowActions.all`. The linter rejects duplicate catalogs. Catalog rules do not accept `style-ok` escapes.
