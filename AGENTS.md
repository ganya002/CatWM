# CatWM

CatWM is a feature-rich but simple macOS tiling window manager.

## What makes CatWM special

We can't compromise on these. They make us what we are today and tomorrow.

- Simple by default: the core works with no setup, and each advanced feature stays out of the way until the user needs it.
- Intuitive: users need to get real work done, not tinker with a tiling manager. CatWM should feel native and obvious.
- Fast and smooth: performance is a core feature, and most apps ignore it. CatWM moves every window, so a slow frame or a hang is a bug. Measure it, and do not trade it for convenience.

## General principles

- Channel your inner DRY, YAGNI, KISS and SOLID.
- Build on the shared layer each area already has, such as theme tokens, components or motion helpers. If it can't do what you need, extend it there.
- Write real fixes, not bypasses.
- Keep code in one function unless a part is reused or composable.
- Before adding complexity for a speculative or vanishingly unlikely race or security edge case, explain the concrete failure mode, likelihood and complexity cost to the user and get their buy-in.
- If a short request has two possible meanings, ask one question before you start.
- Call a bug fixed only when a test, log or recording shows it.

## How it works

CatWM is an engine with no GUI, wrapped by an app that draws. Other Mac apps can embed the same engine. The engine reaches the UI only through one surface interface, so the app, embedded mode and tests each plug in their own. Hotkeys, the CLI and the language libraries all run the same named actions through one command registry. One object owns all state. Accessibility events and window scans trigger one refresh, which reconciles the window list, asks the layout for slots and animates the windows into them through one write queue per app. Each workspace is one native macOS Desktop, and CatWM drives the Desktop slide itself. The config is a TypeScript file that runs on its own JavaScript thread, plus an overrides file that Settings writes. A save re-runs only the changed modules and applies only the changed fields. Saving and reopening windows has two layers. The lower layer saves and reopens app windows and knows nothing about CatWM, and the template layer adds workspaces, Desktops, layouts and frames on top.

## Docs

- Before you change an area, read its doc in `docs/`. Use the words defined in `docs/internals/vocabulary.md`.
- When a large feature adds or reshapes an area, write or update its doc in `docs/internals/` in the same change. The code shows what it does, so the doc records why: each architectural decision, the alternative you rejected and the constraint that decided it.
- Keep docs tight. State each fact once, in the doc that owns it, and delete what has gone stale in the same change that made it stale.

## Checks

- Build: run `./build.sh --dev`. Run `./build.sh` only for a release build. A build stops the running CatWM only with `--replace`. Set `CATWM_INSTANCE=<id>` to build next to it.
- The build writes the schema, the clients and the config docs. Add the changed generated files to your change.
- Lint: `Tools/check-style.sh` and `Tools/swiftlint.sh` must pass. Each failure names its fix.
- Test: run `swift test`. Test the real implementation instead of copying its logic into the test.

## Branches and pull requests

- Use a short branch name of at most three hyphenated words, such as `session-recovery` or `fix-scroll-state`.
- Make a PR only when asked.
- Title it as a conventional commit in plain English: `feat(animation): force windows to render faster`.
- Start the body with one or two sentences on the problem. Then add media such as screenshots (through `--attach`, never committed) or benchmark results in a grid. Under `## Changes`, list what you changed, then add a short section on how you verified it. Leave out lint and style checks.
- Watch the PR until it merges, and resolve conflicts and comments. Verify each reported bug or review issue, and fix only the ones you verified.

## Code and residue

- Agents read code well, so add comments only where the code can't speak for itself.
- Keep plans, research notes and scratch files outside the worktree.
