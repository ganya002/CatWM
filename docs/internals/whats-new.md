# What's New

What's New shows existing users the features of a new release. It can also start a catch-up tour that teaches the new keys.

## How it works

- `Release.all` (`Onboarding/WhatsNew/Release.swift`) is the catalog. Put the newest release first.
- `WhatsNew` keeps the ids of the features that the user saw in the `whatsNew.seen` default.
- At launch, a user who did not finish onboarding gets every current feature marked as seen. The tour already teaches the current app.
- At launch, if a feature is not seen, the card opens below the menu bar icon. If CatWM is busy (onboarding, Overview, window mode), it tries again later.
- When the card opens, its features are marked as seen. The menu shows "What's New…" with a dot until then. After that, the item is in Help.
- "Show me" starts `CatchUpLesson`. The lesson joins the `tour` steps of each shown feature and adds a last step.

## Add a release

1. Add a `Release` at the top of `Release.all`.
2. Give each feature an id that starts with the version, for example `0.4.stacks`. Never change or reuse an id. A changed id shows the feature again.
3. Write the title as one short line. Write the text in two lines or less. Follow the voice rules in `docs/design/design-system.md`.
4. Optional: add an `action` that opens the place where the user can try the feature, for example a Settings pane.
5. Optional: add a `tour` that returns `PlannedStep` values. Use the steps in `Onboarding/Lessons/` or add new ones there. A step completes only when the user presses the real key.
