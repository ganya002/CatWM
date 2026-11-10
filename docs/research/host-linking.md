# How host apps link CatWM

Research for [#344](https://github.com/noxaur/CatWM/issues/344), part of the map [#339](https://github.com/noxaur/CatWM/issues/339). Researched 2026-11-10 against CatWM `main` at `9fec411`.

## Answer

Ship embedded mode as a **source SwiftPM library product, linked statically**, with library evolution off. Split today's single executable target into a library target that holds the window manager and a thin `CatWM` executable that adds the app-only parts. Embedded mode needs none of the three third-party packages: Sparkle, MacKeys and PermissionFlow all serve the app's own GUI, updates or permission UI, and the host draws its own GUI. `sqlite3` is a macOS system library and doesn't leak.

For hosts that aren't written in Swift, add a **small C ABI target later**, on top of the Swift API, using Swift 6.3's `@c` attribute. It can mirror the socket protocol (JSON commands in, JSON events out) so the C surface stays tiny. An **xcframework** is only worth building when a host can't build Swift from source. It forces library evolution on the public API, and a static xcframework can't carry resources.

## What CatWM looks like to a linker today

Measured on the copy installed in `/Applications/CatWM.app` (arm64 only):

| Part | Size |
|---|---|
| `Contents/MacOS/CatWM`, as shipped | 18,873,216 B |
| the same binary after `strip -x` (local symbols removed) | 8,266,864 B |
| the same binary after `strip` (all removable symbols) | 8,112,112 B |
| `__TEXT` segment | 7.16 MB |
| `__LINKEDIT` segment (symbols, signature) | 11.2 MB |
| `Sparkle.framework` (dynamic, in `Contents/Frameworks`) | 2.8 MB |
| `MacKeys_MacKeysCore.bundle` | 396 KB |
| `PermissionFlow_PermissionFlow.bundle` | 48 KB |
| `Fonts`, `AgentDocs` (copied by `build.sh`) | 252 KB, 88 KB |

`nm` lists 60,983 symbols in the shipped binary, so the shipped binary isn't stripped. `build.sh` runs `swift build -c release` and copies the binary without a strip step. **About 10.6 MB of today's "~18 MB" is symbol table.** A host's own release link and strip remove it, so the number a host pays is near the 8 MB stripped figure, minus whatever the split leaves out. The +2 MB budget should name its baseline: stripped or unstripped. This also matters outside embedded mode. Stripping the shipped app would cut it by more than half.

`otool -L` shows the only non-system dynamic dependency is `@rpath/Sparkle.framework`. MacKeysCore, MacKeysUI and PermissionFlow are linked statically into the binary.

Where the third-party code is used (from `grep import` in `Sources/CatWM`):

- **Sparkle**: only `App/Updates/Updater.swift`. A host updates itself, so embedded mode doesn't need it.
- **MacKeysCore, MacKeysUI**: `Keys/Keyboard/*` (the keyboard help overlay) and `Settings/Panes/*`, `Settings/Rows/OptionRows.swift` (the shortcut recorder). Both are CatWM's own UI. MacKeysCore also carries a resource bundle loaded through `Bundle.module` (`mackeys-data.json`, read by a `fatalError` path if missing, in `MacKeysCore/Data.swift`).
- **PermissionFlow**: only `App/Permissions/Permission.swift`, the permission panel. The host draws its own permission UI.
- **sqlite3**: `Notifications/Sources/NotificationDatabase.swift` and `Session/Apps/EditorAdapter.swift`. It links `/usr/lib/libsqlite3.dylib`, which ships with macOS.
- **CatalogPlugin**: a build-tool plugin that runs `/usr/bin/python3 Tools/generate-catalogs.py` to write `GalleryRegistry.swift` for the Design Gallery. It's a build-time dependency, not a runtime one, but every host that builds CatWM from source also runs it. Keep it on the app target only.

## Option 1: SwiftPM library product from source

This is how most Swift packages ship, and how CatWM already consumes MacKeys and PermissionFlow.

**Binary size.** The library is compiled with the host's compiler and linked into the host's executable. A static link with dead stripping only keeps reachable code. The host pays roughly the stripped size of the library target. No measurement exists for the split yet. It needs a release build of the library target linked into an empty host.

**Signing and notarization.** A static library becomes part of the host's main executable. The host signs and notarizes it like its own code, so there's no extra step. A dynamic product (`.library(type: .dynamic)`) has to go in `Contents/Frameworks/` ([Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)). Under the hardened runtime, which notarization requires ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)), library validation "prevents a program from loading frameworks, plug-ins, or libraries unless they're either signed by Apple or signed with the same Team ID as the main executable" ([Disable Library Validation entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation)). So the host re-signs the framework with its own team, or turns off library validation, which Apple says makes Gatekeeper run extra checks.

**Swift ABI.** Not needed. The Swift blog says library evolution is for frameworks "built and updated separately from its clients", and that packages built from source don't need it ([Library Evolution in Swift](https://www.swift.org/blog/library-evolution/)). Without it, hosts get full cross-module optimisation, and CatWM's public types can change between releases with only a source break. Versioning then means semver on source, which is the map's open item "Versioning and API stability".

**Resources.** SwiftPM builds one resource bundle per target that declares resources and generates a `Bundle.module` accessor ([Bundling resources with a Swift package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package)). In SwiftPM's native build system, that accessor looks for `<Package>_<Target>.bundle` at `Bundle.main.bundleURL`, then falls back to the absolute build path ([SwiftModuleBuildDescription.swift, `generateResourceAccessor`](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift)). I didn't check the newer Swift Build system or Xcode's own copy step. CatWM's library code has a second problem: `Theme.swift` loads `Fonts` and `main.swift` loads `AgentDocs` from `Bundle.main.resourceURL`. In a host, `Bundle.main` is the host app, so those reads fail. The library target has to declare these as its own resources and read them through `Bundle.module`. Many other `Bundle.main` reads (version string, bundle ID, `CatWMReportURL`, the install check, the relaunch in `CapsLockChord.swift`) also assume CatWM is the main bundle. Those belong to the app target or to host config.

**Leaking dependencies.** Two SwiftPM rules decide what the split must move out of the library target:

- `unsafeFlags` "makes the products containing this target ineligible for use by other packages" ([PackageDescription `BuildSettings.swift`](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Runtimes/PackageDescription/BuildSettings.swift)). CatWM's target passes the `@executable_path/../Frameworks` rpath with `unsafeFlags`. That rpath exists for Sparkle, so it moves to the executable.
- A package required by version can't depend on a branch. SwiftPM reports "package … is required using a stable-version but … depends on an unstable-version package" ([DiagnosticReportBuilder.swift](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageGraph/Resolution/PubGrub/DiagnosticReportBuilder.swift)). CatWM depends on the PermissionFlow fork by `branch: "fix/panel-height-wrapping"`, so a host that writes `from: "x.y.z"` for CatWM fails to resolve. I didn't test whether moving PermissionFlow to the app target is enough. SwiftPM's target-based resolution ([SE-0226](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0226-package-manager-target-based-dep-resolution.md), "partially implemented" in Swift 5.2) disregards targets that no dependency product needs, but the version check may still see the branch pin. Tagging the fork, or putting the library in its own package, fixes it for sure.

Every dependency in the library target becomes the host's dependency too, with its version pinned against the host's own graph. Keeping the library target free of the three packages removes that risk.

**Language.** Only Swift hosts, or hosts with an Xcode project, can use it.

## Option 2: xcframework (static or dynamic)

An XCFramework is "a binary package created by Xcode" that can hold static or dynamic frameworks and libraries, and ships in SwiftPM as a `binaryTarget` ([Creating a multiplatform binary framework bundle](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle), [Distributing binary frameworks as Swift packages](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)).

**Binary size.** A static xcframework costs about the same as option 1. A dynamic one adds the whole framework, since the linker can't dead-strip a dylib's unused exports, plus library evolution's overhead (below).

**Signing and notarization.** Apple recommends signing the xcframework itself (`codesign --timestamp -s <identity>`), and Xcode fails the build if that signature's certificate gets revoked. A dynamic framework carries the same library-validation constraint as in option 1. The host still re-signs it with its own team when it embeds.

**Swift ABI.** A Swift module in a binary has to be built with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, which "enables support for library evolution and generation of a module interface file" (Apple, as above). The Swift blog lists the costs. Structs and enums pass indirectly at the boundary, protocol calls go through dispatch thunks, it "can increase code size", and switches over non-frozen public enums need `@unknown default`. Turning it on later is itself "a binary-incompatible change", and adding or removing `@frozen` later is too ([Library Evolution in Swift](https://www.swift.org/blog/library-evolution/)). The costs apply across the module boundary. They wouldn't touch the 120 Hz `Animator` loop inside CatWM, but they would touch every host call into the API.

**Resources.** Apple's guide packages a static library with only `-library` and `-headers`, with no option for resources. So CatWM's fonts and data would ship as separate bundles that the host copies by hand. A `.framework` bundle keeps resources in `Versions/A/Resources/` ([Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)).

**Leaking dependencies.** A binary target is only the artifact, so each third-party package would be either baked into CatWM's binary, where it can clash with the host's own copy of the same symbols, or shipped as another xcframework. Apple also warns that "binary dependencies are only available for Apple platforms", which is fine for CatWM.

**Prior art.** Sentry ships every variant as a separate `binaryTarget` xcframework on GitHub Releases: `Sentry` (static), `Sentry-Dynamic`, `Sentry-WithoutUIKitOrAppKit` and others ([sentry-cocoa `Package.swift`](https://github.com/getsentry/sentry-cocoa/blob/main/Package.swift)). Sparkle, which CatWM already uses, ships a single `binaryTarget` pointing at `Sparkle-for-Swift-Package-Manager.zip` ([Sparkle `Package.swift`](https://github.com/sparkle-project/Sparkle/blob/2.x/Package.swift)). Sentry shows the cost: one xcframework per variant, per release, with checksums kept in the manifest.

**Language.** It works with any build system that links an Xcode artifact. On its own it doesn't help an Electron, Tauri or Qt host call Swift.

## Option 3: C ABI for non-Swift hosts

**Mechanism.** Swift 6.3 ships `@c` (SE-0495, status "Implemented (Swift 6.3)"), which formalises the long-used `@_cdecl`. It marks global Swift functions and enums as callable from C, type-checks that they only use C-representable types, and prints them into a C block of the generated header. It also allows `@c @implementation` against a hand-written header ([SE-0495](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0495-cdecl.md)). The local toolchain is Swift 6.4.2, so this is available now.

**Prior art.**

- **Rust and Tauri**: `swift-rs` asks for a Swift package built as `type: .static`. Exported functions must be `@_cdecl`, and `SwiftLinker` in `build.rs` links the package and the Swift runtime. Its README warns that Tauri hosts hit `Library not loaded: @rpath/libswiftCore.dylib` unless the minimum macOS version is 10.15 or higher ([swift-rs](https://github.com/Brendonovich/swift-rs)). CatWM's macOS 14 minimum avoids that.
- **Electron and Node**: NodeSwift builds a SwiftPM package into a `.node` addon over Node-API, aimed at "using native macOS APIs and SwiftPM in an Electron app" ([node-swift](https://github.com/kabiroberai/node-swift)). It's Swift-to-Node-API directly, not a C header, but it shows an Electron host loading a Swift package in its own process.
- **The reverse direction**: Ghostty's macOS app is Swift and embeds a Zig core through a C header (`include/ghostty.h`). The header's own comment says the API is "tailored to the needs of the macOS app and not designed for external use", and points external embedders to a separate, documented library ([ghostty.h](https://github.com/ghostty-org/ghostty/blob/main/include/ghostty.h)). The lesson is to keep the C surface separate from the internal API and designed for outsiders.

**Cost.** Each C function needs C types only: opaque handles, C strings, function-pointer callbacks with a context pointer, and explicit ownership rules. That's a second API to design and version. CatWM already has a language-neutral surface, though. Every CLI command and every event is JSON over the socket, from one registry (`docs/internals/control.md`). A C ABI could be a few functions: create, start, stop, `dispatch(json) -> json`, and `subscribe(callback)`. Those would call the same `CommandRegistry` and `EventBus` in-process, which keeps the C surface small and reuses the generated schema and clients. This is a design suggestion, not an existing pattern in the repo.

**Size, signing, ABI, resources.** These are the same as the static options above. The C target is a thin layer over the Swift library. Its ABI is C, so it's stable by construction and doesn't need library evolution. A non-Swift host gets it either as a static library plus header (an xcframework built with `-library … -headers …`), or as a dylib with the library-validation rule above.

## Permissions

This isn't a linking option, but it follows from linking in-process. `AXIsProcessTrusted()` "returns whether the current process is a trusted accessibility client" ([Apple](https://developer.apple.com/documentation/applicationservices/axisprocesstrusted())). In embedded mode, the current process is the host, so the Accessibility grant (and Input Monitoring for the event tap) belongs to the host app's signature, not to CatWM. Every option above behaves the same way, which is another reason PermissionFlow and CatWM's permission panel stay in the app.

## Recommendation

1. Split `Package.swift` into a library target (proposed name `CatWMKit`) and the `CatWM` executable. Move to the executable: `Updater`, `Settings`, `Onboarding`, the keyboard overlay that uses MacKeys, `Permission`, `CatalogPlugin`, the `unsafeFlags` rpath and the `Bundle.main` app checks. Give the library its own `resources:` for `Fonts` and any data it reads.
2. Ship `CatWMKit` as a static, source-only `.library` product with library evolution off. Tag the PermissionFlow fork, or move the library into a package without it, so version-based resolution works.
3. Measure before deciding further. Link the library into an empty AppKit host in release mode, strip it, and compare against the stripped 8.1 MB app binary. Set the +2 MB budget against that stripped baseline.
4. Add a `CatWMC` target with `@c` functions over the command registry once the first non-Swift host is real. Ship it with a header in a static xcframework at that point.
5. Don't build a dynamic or Swift-API xcframework unless a host can't build from source. It brings library evolution, per-release binaries and re-signing.

## Not verified

- The size of the library target alone after the split. That needs the split and a release build.
- Where Xcode and Swift Build place package resource bundles in a host `.app`, and how their `Bundle.module` accessor looks them up. I only read SwiftPM's native build system source.
- Whether MacKeysCore is needed by the parts of the keyboard hint system that embedded mode keeps. That depends on what embedded mode exposes, which belongs to a later ticket.
