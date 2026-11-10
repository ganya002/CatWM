import AppKit
import QuartzCore

package final class NativeDesktopController {
    package struct Request: Equatable {
        package let workspace: String
        package let display: String
        package let space: UInt64
    }
    package typealias Settings = MotionSpec
    package var settings = MotionSpec(duration: 0.18, curve: .easeOut, bounce: 0.5)
    package var prepare: (Request) async throws -> Void = { _ in }
    package var onSettled: (Request, _ changed: Bool) -> Void = { _, _ in }
    package var onMotion: (Request) -> Void = { _ in }
    package var isForward: (_ source: UInt64, _ target: UInt64, _ desktopOrder: Bool) -> Bool = { $2 }
    package var onIdle: () -> Void = {}
    package var onFailure: (String) -> Void = { _ in }
    package var guarded = true
    package private(set) var requested: Request?
    package private(set) var isRunning = false
    private var gesture = false
    private var gestureEnded = true
    private var gestureProgress = 0.0
    private var requestedAt: CFTimeInterval = 0
    @MainActor private var timing: DesktopTransitionTiming?
    @MainActor private var warmGuard: DesktopGuardClient?

    package func request(_ target: Request, since start: CFTimeInterval = CACurrentMediaTime()) {
        requested = target
        requestedAt = start
        gestureEnded = true
        self.start()
    }

    package func beginGesture(_ target: Request) {
        guard !isRunning else { return }
        requested = target
        requestedAt = CACurrentMediaTime()
        gesture = true
        gestureEnded = false
        gestureProgress = 0
        start()
    }

    package func scrub(_ value: Double) { gestureProgress = min(1, max(0, value)) }

    package func endGesture(commit: Bool) {
        gestureEnded = true
        if !commit { requested = nil }
    }

    package func stop() {
        requested = nil
        gestureEnded = true
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor in
            defer { self.isRunning = false; self.gesture = false; self.onIdle() }
            while let target = self.requested {
                do {
                    if self.guarded {
                        try await self.transition(target, since: self.requestedAt)
                    } else {
                        try await self.swipeUnguarded(to: target)
                    }
                } catch {
                    if self.requested == target { self.requested = nil }
                    self.gesture = false
                    self.onFailure(error.localizedDescription)
                    continue
                }
                if self.requested == target { self.requested = nil }
            }
        }
    }

    @MainActor private func transition(_ target: Request, since start: CFTimeInterval) async throws {
        let timing = DesktopTransitionTiming(since: start)
        self.timing = timing; timing.checkpoint("queue")
        guard let screen = Screen.all().first(where: { $0.uuid == target.display }) else {
            throw DesktopTransitionError.check("The display disconnected")
        }
        let source = Spaces.current(display: target.display)
        Log.info("native workspaces: \(source) → \(target.space), workspace \(target.workspace)")
        if source == target.space { onSettled(target, false); return }
        let busy = "Finish the current macOS Desktop action, then try again"
        var list: Spaces.DisplaySpaces?, sourceState: DesktopBridge.State?, targetState: DesktopBridge.State?
        let ready = await poll(1, every: 10_000_000) {
            list = Spaces.list(display: target.display)
            sourceState = DesktopBridge.state(source)
            targetState = DesktopBridge.state(target.space)
            return DesktopUI.isSettled(screen) && sourceState?.transform == .identity
                && targetState?.transform == .identity
                && list.map { $0.ids.contains(source) && $0.ids.contains(target.space) } == true
        }
        guard ready, let list, let from = list.ids.firstIndex(of: source),
              let into = list.ids.firstIndex(of: target.space), let sourceState, let targetState else {
            throw DesktopTransitionError.check(busy)
        }
        let state = DesktopGuard.Context(display: target.display, source: source, destination: target.space,
                                         sourceOptions: sourceState.options, destinationOptions: targetState.options)
        let recovery = acquireGuard()
        timing.checkpoint("ready")
        try await prepareWhileGuarding(target, state, recovery)
        timing.checkpoint("guard/layout")
        if !wants(target) { try await release(recovery); return }
        var failure: Error?
        do {
            try await compose(state, screen: screen, forward: into > from, target: target, recovery: recovery)
        } catch { failure = error }
        state.restore(); try await recovery.restore()
        let restored = await poll(1) {
            DesktopBridge.isIdentity(source) && DesktopBridge.isIdentity(target.space)
                && DesktopBridge.isIdle(display: target.display)
        }
        guard restored else { throw DesktopTransitionError.check("Desktop recovery is still in progress") }
        try await release(recovery)
        if let failure {
            let maximised = !list.desktops.contains(from) || !list.desktops.contains(into)
            guard maximised, wants(target), Spaces.current(display: target.display) != target.space else {
                throw failure
            }
            Log.info("native workspaces: \(failure.localizedDescription); swiping to the maximised window")
            try await swipe(to: target)
        }
        Log.info("native workspaces: restored transforms after \(target.workspace)")
        if Spaces.current(display: target.display) == target.space { onSettled(target, true) }
    }

    @MainActor private func prepareWhileGuarding(_ target: Request, _ state: DesktopGuard.Context,
                                                 _ recovery: DesktopGuardClient) async throws {
        let launch = Task { @MainActor in try await recovery.start(state) }
        var preparation: Error?
        do { try await prepare(target) } catch { preparation = error }
        do { try await launch.value } catch { throw preparation ?? error }
        if let preparation { try? await release(recovery); throw preparation }
    }

    @MainActor private func compose(_ state: DesktopGuard.Context, screen: Screen, forward desktopOrder: Bool,
                                    target: Request, recovery: DesktopGuardClient) async throws {
        let fresh = DesktopMenuBar.isFresh(state.destination)
        DesktopWallpaperCover.shared.prepare(on: screen, source: state.source, target: state.destination, fresh: fresh)
        let forward = isForward(state.source, state.destination, desktopOrder)
        let width = screen.frame.width * (forward ? 1 : -1)
        var progress = 0.0
        try check(DesktopBridge.animating(display: state.display, active: true), "Cannot begin Desktop motion")
        try apply(state, width: width, progress: 0)
        try check(DesktopBridge.willSwitch([state.destination]), "Cannot prepare the destination Desktop")
        try check(DesktopBridge.setVisible([state.destination], true), "Cannot show the destination Desktop")
        onMotion(target)
        let motion = DesktopMotion(screen: screen.nsScreen)
        let covered = DesktopWallpaperCover.shared.isReady(source: state.source, target: state.destination)
        async let drawn: Void = fresh && !covered ? motion.frames(2) : ()
        let menu = try await prepareMenuBar(state, on: screen, recovery: recovery)
        self.timing?.checkpoint("menu")
        defer { menu?.restore() }
        guard wants(target) else { return }
        try await drawn
        let wallpaper = await DesktopWallpaperCover.shared.present(
            source: state.source, target: state.destination, while: { self.wants(target) })
        defer { wallpaper?.end(shown: Spaces.current(display: state.display) == state.destination, settings: settings) }
        guard wants(target) else { return }
        try checkCurrentSource(state)
        self.timing?.checkpoint("show/frames")
        if gesture {
            try await motion.follow(until: { self.gestureEnded }, update: {
                try self.check(recovery.process.isRunning, "Desktop recovery process stopped")
                progress = self.gestureProgress
                try self.apply(state, width: width, progress: progress)
                return progress
            })
            gesture = false
        }
        while true {
            let landing = wants(target) ? 1.0 : 0.0
            do {
                try await motion.animate(from: progress, to: landing, with: settings) { value in
                    guard (self.wants(target) ? 1.0 : 0.0) == landing else { throw Retarget.changed }
                    try self.check(recovery.process.isRunning, "Desktop recovery process stopped")
                    progress = value
                    try self.apply(state, width: width, progress: value)
                }
                break
            } catch Retarget.changed { continue }
        }
        try checkCurrentSource(state)
        if wants(target) {
            try await activate(state, menu: menu, wallpaper: wallpaper, screen: screen, target: target)
        }
    }

    @MainActor private func activate(_ state: DesktopGuard.Context, menu: DesktopMenuBarLease?,
                                     wallpaper: DesktopWallpaperCover.Lease?,
                                     screen: Screen, target: Request) async throws {
        let batch = WindowServerUpdates.shared.begin()
        if let menu, DesktopMenuBarNative.theme(state.destination) == menu.state.theme { menu.restore() }
        try check(DesktopBridge.setVisible([state.source], false), "Cannot hide the source Desktop")
        try check(DesktopBridge.setCurrent(display: state.display, space: state.destination),
                  "Cannot activate the destination Desktop")
        batch?.finish()
        let arrived = await poll(1) { Spaces.current(display: state.display) == state.destination }
        try check(arrived, "macOS did not activate the destination Desktop")
        wallpaper?.end(shown: true, settings: settings)
        DesktopMenuBar.shown(state.destination)
        try await DesktopMenuBar.settle(menu?.state, on: screen, while: { self.wants(target) })
        await menu?.finish()
    }

    @MainActor private func prepareMenuBar(_ state: DesktopGuard.Context, on screen: Screen,
                                           recovery: DesktopGuardClient) async throws -> DesktopMenuBarLease? {
        guard DesktopMenuBar.needsPreparation(source: state.source, target: state.destination) else { return nil }
        let cover = DesktopMenuBarCover.shared
        async let image = cover.capture(on: screen, source: state.source, target: state.destination)
        let background = await DesktopMenuBar.ready(source: state.source, target: state.destination, screen: screen)
        timing?.checkpoint("menu-ready")
        guard let background else { DesktopMenuBarCover.shared.recycle(await image); return nil }
        do {
            try background.persist()
            var guarded = state
            guarded.menuBar = background
            try await recovery.update(guarded)
            guard DesktopBridge.detachMenuWindows([background.window], from: background.space),
                  await poll(0.1, every: 250_000, until: { Spaces.of(window: background.window).isEmpty }) else {
                throw DesktopTransitionError.check("Cannot prepare the Desktop background")
            }
        } catch {
            background.restore(); DesktopMenuBarCover.shared.recycle(await image)
            throw error
        }
        timing?.checkpoint("menu-guard")
        let panel = await image
        timing?.checkpoint("menu-cover")
        if panel == nil {
            Log.info("native workspaces: no menu bar cover, screen recording "
                        + "\(PermissionWatcher.shared.granted.contains(.screenRecording))")
        }
        _ = DesktopMenuBarNative.alpha(background.space, 0)
        return DesktopMenuBarLease(state: background, panel: panel)
    }

    private enum Retarget: Error { case changed }

    @MainActor private func swipe(to target: Request) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func remaining() -> TimeInterval { deadline - ProcessInfo.processInfo.systemUptime }
        while Spaces.current(display: target.display) != target.space {
            if !wants(target) { return }
            guard remaining() > 0,
                  let list = Spaces.list(display: target.display), let current = list.current,
                  let destination = list.ids.firstIndex(of: target.space) else {
                throw DesktopTransitionError.check("macOS did not reach the Desktop")
            }
            let source = list.ids[current]
            try check(DesktopSwipe.post(right: destination > current), "Native Desktop navigation is unavailable")
            try await check(poll(remaining(), every: 20_000_000) { Spaces.current(display: target.display) != source },
                            "macOS did not change Desktop")
            try await check(poll(remaining(), every: 20_000_000) { DesktopBridge.isIdle(display: target.display) },
                            "macOS did not finish changing Desktop")
        }
    }
}

extension NativeDesktopController {
    @MainActor private func apply(_ state: DesktopGuard.Context, width: CGFloat, progress: Double) throws {
        let pose = min(1, max(0, progress))
        if pose > 0 { timing?.motion() }
        try check(DesktopBridge.transform(state.destination, x: (pose - 1) * width,
                                          options: state.destinationOptions), "Cannot move the destination Desktop")
        try check(DesktopBridge.transform(state.source, x: pose * width, options: state.sourceOptions),
                  "Cannot move the source Desktop")
    }

    private func wants(_ target: Request) -> Bool {
        guard let requested else { return false }
        return requested == target || requested.display != target.display
    }

    private func checkCurrentSource(_ state: DesktopGuard.Context) throws {
        try check(Spaces.current(display: state.display) == state.source,
                  "Native navigation interrupted Desktop switching")
    }

    private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw DesktopTransitionError.check(message) }
    }

    @MainActor package func prewarmGuard() {
        guard guarded else { return }
        DesktopWallpaperCover.shared.prepare()
        guard warmGuard?.process.isRunning != true else { return }
        let client = DesktopGuardClient()
        if (try? client.launch()) != nil { warmGuard = client }
    }

    @MainActor private func acquireGuard() -> DesktopGuardClient {
        defer { warmGuard = nil }
        if let warmGuard, warmGuard.process.isRunning { return warmGuard }
        return DesktopGuardClient()
    }

    @MainActor private func release(_ recovery: DesktopGuardClient) async throws {
        try await recovery.release()
        if warmGuard?.process.isRunning != true {
            warmGuard = recovery
        } else if warmGuard !== recovery {
            try await recovery.shutDown()
        }
    }
}

extension NativeDesktopController {
    @MainActor func swipeUnguarded(to target: Request) async throws {
        let changed = Spaces.current(display: target.display) != target.space
        try await swipe(to: target)
        if Spaces.current(display: target.display) == target.space { onSettled(target, changed) }
    }
}
