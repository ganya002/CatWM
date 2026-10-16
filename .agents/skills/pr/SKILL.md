---
name: pr
description: Create a pr
---

## Merge conflicts

Before you create the pull request, merge the base branch into your branch. Resolve all merge conflicts yourself. Keep the intent of both sides, remove the conflict markers, and run the project checks.
## Title

Use the PR title standard of the project. Look for it in `CONTRIBUTING.md`, the PR template, and `CLAUDE.md` or `AGENTS.md`.

If the project has no standard, use this fallback:

- Write one imperative sentence, for example "Add workspace switch animation".
- Use sentence case. Do not put a period at the end.
- Keep the title at 72 characters or fewer.
- Do not use prefixes such as `feat:` or `[WIP]`.

## Description

Create a pull request with this description structure, in order:

1. Explain the problem in 1–3 sentences.
2. For UI changes, include before/after screenshots or videos in a two-column Markdown table labeled Before and After.
3. List the changes as an unordered list.
4. Explain in sentences how the changes were verified. State any verification not performed.

Put each section after the problem and the media under a `##` heading, for example `## Changes` and `## Verification`. Do not put a heading above the problem or the media.

<!--
Media rules for step 2:
- If you have no image or video, do not include step 2.
- If you have only one image or video, add it alone. Do not use the table.
-->
