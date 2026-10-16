# Surface

Surface is the single floating container behind every menu, tooltip, tip, coach mark, HUD and welcome card.

Provide `density` (`xs`, `sm`, `md`, `lg`, `xl`), optional `tone="accent"`, `glass`, `caret` (`top`, `bottom`, `left`) with `caretAt`, and any slots: `lead` (symbol name), `kicker`, `onClose`, `headEnd`, `title`, `body`, `keys`, children, `actions`, `progress`.

- Pick the density by job, not by size: tooltip `xs`, confirmation `sm`, menu or tip `md`, tour step `lg`, welcome `xl`.
- Slots always appear in the same order; leave a slot out rather than reordering.
- Anything with a button is `md` or larger. Coach marks always point at a real target with the caret.
