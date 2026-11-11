---
name: update
description: Add a What's New entry for the newest changes
---

1. Find the features that merged after the last entry in `Sources/CatWM/Onboarding/WhatsNew/Release+all.swift`: `git log`. Skip fixes and internal work.
2. Add each feature to `Release.all`, newest first. Start its id with the version, such as `0.4.stacks`, and never change or reuse an id: `WhatsNew` stores seen ids, so a changed id shows the feature again. Write the title as one short line and the text in two lines or less, in the voice of `docs/design/design-system.md`.
3. Add a `tour` when the user can try the feature with a key. Put new steps in `Sources/CatWM/Onboarding/Lessons/`.
4. Run `swift build`, `swift test`, `Tools/check-style.sh` and `swiftlint`.
