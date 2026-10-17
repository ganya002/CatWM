---
name: pr
description: Create a pr
---

## Merge conflicts

Before creating pull request, merge base branch into your branch. Resolve merge conflicts yourself. Keep intent of both sides and run the project checks.

## Text

Use project's standard from `CONTRIBUTING.md`, the PR template, or `CLAUDE.md` / `AGENTS.md`. Otherwise write one imperative sentence in sentence case
Example: "Add workspace switch animation".

## Description

In order:

1. The problem, in 1–3 sentences. No heading.
2. For a UI change, a Before/After table directly under the problem, with no heading. One image or video goes alone, without the table. Skip this when there is no media.
3. `## Changes`, as an unordered list.
4. `## Verification`, in sentences, including any verification not performed.

Upload images and videos with `gh` `--attach`. Do not commit them. Put the local paths in the table and pass those same paths to `--attach`, so `gh` rewrites them in place.

```markdown
The form accepts a blank password.

| Before                  | After                 |
| ----------------------- | --------------------- |
| ![Before](./before.png) | ![After](./after.png) |
```

```shell
gh pr create --body-file pr.md --attach ./before.png --attach ./after.png
```

`gh pr edit` without `--body` appends the file. Pass the full body when the image belongs in the table.

## Until merged

Watch the pull request. Resolve conflicts and fix failing checks or review issues until it is merged.
