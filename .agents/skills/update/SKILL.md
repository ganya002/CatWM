---
name: update
description: Add a What's New entry for the newest changes
---

1. Find the features that merged after the last entry in `Sources/CatWM/Onboarding/WhatsNew/Release+all.swift`: `git log`. Skip fixes and internal work.
2. Add each feature to `Release.all`, newest first. Follow `docs/internals/whats-new.md`.
3. Add a `tour` when the user can try the feature with a key. Put new steps in `Sources/CatWM/Onboarding/Lessons/`.
4. Run `swift build`, `swift test`, `Tools/check-style.sh` and `swiftlint`.
