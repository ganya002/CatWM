# LayoutThumb

LayoutThumb draws a miniature of one of the 13 tiling layouts.

Provide `layout`, `width` (height follows at 16:10), `selected`. Panes are `tint` and the main pane a darker neutral (`ink-muted` mixed into `tint`); when `selected`, the main pane turns `accent`.

- Use the layout descriptions from `LayoutThumb.layouts[k].desc` as tooltips; they are the app's own copy.
