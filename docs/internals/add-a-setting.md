# Add a setting

1. Add a property to `Config`.
2. Add one option declaration with `.setting(...)` in `Config/Options/Options.swift`. Set its section, order, range, and enabled state there. Effect descriptors can publish their options beside the effect.
3. Run `./build.sh --dev`. It generates `Resources/AgentDocs/config.md` from the option declarations and `config.template.md`.

`OptionRows` renders the declaration. Settings search reads the same declaration. Keep custom controls in that renderer. Put pointer behavior in `PointerActions` or its effect descriptor. The build collects custom search entries and palette tokens. Dispatcher names come from `WindowActions.all`. The linter rejects duplicate catalogs. Catalog rules do not accept `style-ok` escapes.
