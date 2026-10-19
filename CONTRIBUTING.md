# Contributing to Ouch

Thank you for your help. This page tells you how to set up, check and submit a change.

## Set up

- Use a Mac with macOS 14 or later and the Swift toolchain (Xcode or the Command Line Tools).
- Run `brew install swiftlint`.
- Clone the repository and run `./build.sh --dev`. This also installs the git hook.

## Build and run

- `./build.sh --dev` makes a fast debug build in `build/ouch.app`. Use it while you work.
- `./build.sh` makes a release build. Do not ship a `--dev` build.
- `open build/ouch.app` starts the app.
- The app is ad-hoc signed. Each rebuild cancels its Accessibility permission. Click **Reset Permission** in Settings, then turn Ouch on again.

## Check your change

- `Tools/check-style.sh` must pass. The pre-commit hook, `swift test`, `./build.sh` and the `lint` GitHub Actions workflow run it.
- Run `swiftlint`.
- Run `swift test`. If you have only the Command Line Tools, add `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`.
- Do not write code comments. The style check rejects them. A deliberate one-off ends with `// style-ok: <reason>` on that line.

## Where to read first

- `AGENTS.md` has the code map, the vocabulary and the project rules.
- `docs/design/design-system.md` tells how each UI component must look. Read it before you change UI.
- `docs/internals/add-a-setting.md` tells how to add a setting.
- `docs/internals/` also holds the reasons and constraints behind some designs.

## Submit a change

- Write commit messages in English: `type(scope): description`. The scope is optional.
- Write the pull request title as one imperative sentence in sentence case. Example: "Add workspace switch animation".
- Write the pull request body in this order: the problem in 1 to 3 sentences, a `## Changes` heading with an unordered list, and a `## Verification` heading that says how you verified the change.
- For a UI change, attach a before image and an after image. For motion, attach a video. Upload them to the pull request. Do not commit them.
- Verify a bug before you fix it. Fix only bugs that you verified.
