---
name: roadmap
description: Add, link or move a card on the CatWM roadmap (catwm.perwko.com/roadmap). Use when you start or finish a feature, open a PR, or have an idea to track.
---

GitHub keeps the roadmap current. Use GitHub first. Use the API only when no issue or PR fits.

1. **An idea or a planned feature:** `gh issue create --label roadmap`. The webhook adds a card in Ideas, flagged questionable, so a developer reviews it. Add the `planned` label to move it to Planned.
2. **A PR for a card:** put one of these lines in the PR body.
   - `Closes #12` (or Fixes, Resolves) for a card with the ref `#12`.
   - `Roadmap: <card id>` for a card with no issue. Find the id with the API below.
   Opening the PR moves the card to In progress, merging moves it to Shipped, and closing without a merge moves it back to Planned.
3. **A feature PR with no card:** add the `roadmap` label to the PR. The card comes in as questionable.
4. **Fixes, refactors and internal work:** do nothing. They do not go on the roadmap.

The API, with `ROADMAP_TOKEN` from the user (never commit it):

```sh
curl -s -H "Authorization: Bearer $ROADMAP_TOKEN" https://catwm.perwko.com/api/roadmap | jq '.cards[] | {id, title, column, ref}'
curl -s -H "Authorization: Bearer $ROADMAP_TOKEN" https://catwm.perwko.com/api/roadmap \
  -F intent=move -F id=<card id> -F column=planned -F questionable=0
```

`intent` is `move` (`id`, `column`, `questionable`, optional `before`), `save` (`id`, `title`, `line`, `area`, `column`, `questionable`, `note`, `ref`) or `remove` (`id`). Columns are `idea`, `planned`, `doing` and `done`. Areas are listed in `website/app/roadmap/model.ts`.
