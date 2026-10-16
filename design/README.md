# Ouch design system

Open `index.html` in a browser. Run `open design/index.html`. It needs no server and no build step.

## Files

- `index.html`: every component, with its rules and its markup, and every token. One section per component.
- `tokens.css`: the tokens (colour, space, radius, shadow, size and type) as CSS variables. Light and dark are two blocks: `:root` and `[data-theme="ouch-dark"]`.
- `components.css`: the styles of the components. Class names start with `o-` (`o-btn`, `o-switch`, `o-menu`).
- `fonts/`: the Chillax font.

## How to change something

- **A colour, space, radius, shadow or size:** edit the variable in `tokens.css`. Change both the light and the dark block. Every component updates.
- **How a component looks:** edit its `o-` classes in `components.css`.
- **A component rule or its example:** edit its section in `index.html`. The text above the example is the rule. The markup in the example is the real markup.
- **A new component:** copy a section in `index.html`, give it a new `id`, and add a link to it in the `nav`.

Do not type a raw colour, size or time in `components.css`. Use a variable from `tokens.css`.

## Keep the app in step

The app reads its values from `Sources/ouch/UI/Theme.swift`, not from these files. When you change a token or a component here, change `Theme.swift` and `Components.swift` to match. `docs/design-system.md` maps each component to its Swift type.
