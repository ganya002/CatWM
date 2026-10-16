# Symbol

Symbol draws an SF Symbol by its real name and plays one of its effects.

Provide `name` (an SF Symbol name), optional `effect` (`bounce`, `wiggle`, `rotate`, `pulse`, `breathe`, `variable`, `replace`, `draw`, `appear`, `scale`), `trigger` (change it to replay a discrete effect), `size`, `weight` and `label` for symbols that carry meaning alone.

- Discrete effects (`bounce`, `wiggle`, `rotate`) report that something just happened; bind them to a counter.
- Indefinite effects (`pulse`, `breathe`, `variable`) report a state that lasts; switch them off when it ends.
- `replace` is for one control changing state (tiling on/off), never for unrelated icons.
- The web drawings are stand-ins; in SwiftUI use `Image(systemName:)` with the effect listed in the README's symbol table.
- Don't animate a symbol on every hover except `scale` in menu rows.
