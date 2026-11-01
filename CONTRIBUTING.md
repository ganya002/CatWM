# Contributing to CatWM

Thank you for your help. This page tells you how to set up, check and submit a change. It also tells how to install a local build, run the feedback relay and make a release.

## Set up

- Use a Mac with macOS 14 or later and the Swift toolchain (Xcode or the Command Line Tools).
- Install SwiftLint 0.65.1. See [Lint](#lint).
- Clone the repository and run `./build.sh --dev`. This also installs the git hook.

## Build and run

- `./build.sh --dev` makes a fast debug build in `build/CatWM.app`. Use it while you work. It takes a few seconds, not approximately a minute.
- `./build.sh` makes a release build. Do not ship a `--dev` build.
- `open build/CatWM.app` starts the app.
- `./install.sh` installs a beta build to `/Applications/CatWM.app` and opens it. Add `--stable` to remove the beta channel marker.
- The app is ad-hoc signed. Each rebuild cancels its Accessibility permission. CatWM shows ⚠️ in the menu bar and opens Settings. Click **Reset Permission**, then turn CatWM on again.

### Launch arguments

- `open build/CatWM.app --args --onboarding` plays the onboarding again.
- `open build/CatWM.app --args --verbose` writes a detailed log. The old `debug-logging` config key also works.
- `open build/CatWM.app --args --crash-report` sends the newest crash report, to test the upload.

## Check your change

- `Tools/check-style.sh` must pass. The pre-commit hook, `swift test`, `./build.sh` and the `lint` GitHub Actions workflow run it.
- Run `Tools/swiftlint.sh`. See [Lint](#lint).
- Run `swift test`. If you have only the Command Line Tools, add `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`.
- Do not write code comments. The style check rejects them. A deliberate one-off ends with `// style-ok: <reason>` on that line.

### Lint

SwiftLint needs the Xcode tools. Install Xcode, or install the Command Line Tools with `xcode-select --install`.

The project pins SwiftLint 0.65.1. `.swiftlint.yml` sets `swiftlint_version`, so a different version stops with an error. Install that version from the [0.65.1 release](https://github.com/realm/SwiftLint/releases/tag/0.65.1), or with Homebrew while 0.65.1 is the current formula:

```sh
brew install swiftlint
swiftlint version
```

Run it from the repo root:

```sh
Tools/swiftlint.sh
```

The pre-commit hook and `./build.sh` run it too. If you have only the Command Line Tools (no Xcode), the script gives SwiftLint the SourceKit path.

The config is strict: all default rules are on, more opt-in rules are on, and each warning is an error. Comments are not permitted in this repo, so you cannot disable a rule in the code. Fix the code. The `lint` workflow runs SwiftLint 0.65.1 on each push and pull request.

## Where to read first

- `AGENTS.md` has the code map, the vocabulary and the project rules.
- `docs/design/design-system.md` tells how each UI component must look. Read it before you change UI.
- `docs/internals/add-a-setting.md` tells how to add a setting.
- `docs/internals/` also holds the reasons and constraints behind some designs. For example, [native-space-import.md](docs/internals/native-space-import.md) tells how **Bring Window Here** and Dock clicks move a window from a different macOS Desktop.

## Submit a change

- Write commit messages in English: `type(scope): description`. The scope is optional.
- Write the pull request title like a commit message: `type(scope): description`. Example: `feat(animation): add workspace switch animation`. The type sets the type label.
- Write the pull request body in this order: the problem in 1 to 3 sentences, a `## Changes` heading with an unordered list, and a `## Verification` heading that says how you verified the change.
- For a UI change, attach a before image and an after image. For motion, attach a video. Upload them to the pull request. Do not commit them.
- Verify a bug before you fix it. Fix only bugs that you verified.
- The `label-pr` workflow labels each pull request with its size (`size/XS` to `size/XXL`), its scopes (`scope: tiling`), its type from the title (`bug`, `enhancement`) and `vouched` or `unvouched`. Do not set these by hand. The workflow resets them on each push.

## Feedback and performance relay

**Send feedback** in Settings sends the report to the relay in `report-relay/`. The relay is a Cloudflare Worker that keeps the Linear API key. A key in the app is not safe, because a user can extract it. The relay makes a Linear issue for each report. Deploy it one time:

```sh
cd report-relay
npx wrangler deploy
npx wrangler secret put LINEAR_API_KEY   # Linear → Settings → Security & access → Personal API keys
```

Set `LINEAR_TEAM_ID` in `wrangler.toml` to the UUID of the team. Put the URL of the worker plus `/report` into `CatWMReportURL` in `Info.plist`.

`PerfMonitor` (`Sources/CatWM/App/Perf/PerfMonitor.swift`) measures the frames while CatWM moves windows and plays its panels. It also measures the AX cost for each app and main-thread hangs of more than 250 ms. Each slowdown goes to `CatWM.log` as a `perf:` line. With `perf-reports = true` (off by default), CatWM sends a slowdown to the `/perf` route after it occurs 5 times, or 2 times for a hang of more than 1 s. CatWM logs, but does not send, runs on a hot, low-power or loaded Mac. It sends each fingerprint one time in 7 days, a maximum of one time each day and 5 times each week.

The relay makes one Linear issue for each fingerprint (`[perf:<id>]` in the title) and adds a comment for each repeat, to a maximum of 10. Its API key needs the read and create comment scopes, and the create issues scope. Set `LINEAR_PERF_LABEL_ID` to add a label to the issues.

After a crash, a small watchdog opens CatWM again when macOS has written the crash report. CatWM then sends the crash report, the log up to the crash, the config and the Mac setup to the relay. If the send fails, it tries again at the next launch.

## Releasing

Updates ship through [Amore](https://amore.computer) and Sparkle. Amore signs, notarizes, builds the DMG, writes the appcast and hosts it.

One-time setup:

```sh
amore login
./build.sh
amore setup build/CatWM.app --hosting amore --generate-sparkle-key
```

Put the feed URL and the public key that it prints into `SUFeedURL` and `SUPublicEDKey` in `Info.plist`. Until you do this, the app does not check for updates.

The build number comes from the commit count, so you only change `CFBundleShortVersionString` by hand. For each release:

```sh
./release.sh "What changed"                      # build, sign, notarize, publish
./release.sh "Try this first" --channel beta     # beta channel (Settings → General → Updates → Include beta releases)
./release.sh "Security fix" --critical           # tells users to update immediately
./release.sh "Big change" --phased-rollout       # gradual rollout
./release.sh "WIP" --draft                       # upload, but do not publish
```

For early-access betas, `./beta.sh "What changed"` publishes to the beta channel and does not change the version. The build number is the commit count and the version is `0.2-beta.<build>`. Beta builds start with beta updates on. Without a Developer ID certificate, it ships an unsigned ZIP. Testers must permit it one time in System Settings → Privacy & Security → **Open Anyway**.

The install script for testers is [website/public/install.sh](website/public/install.sh). The website serves it at `https://catwm.perwko.com/install.sh`.
