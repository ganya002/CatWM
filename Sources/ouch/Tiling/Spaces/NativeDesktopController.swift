import AppKit

final class NativeDesktopController {
    struct Request: Equatable {
        let workspace: String
        let display: String
        let space: UInt64
    }
    struct Settings {
        let duration: Double
        let curve: AnimationCurve
        let bounce: Double
    }
    var settings = Settings(duration: 0.18, curve: .easeOut, bounce: 0.5)
    var prepare: (Request) async throws -> Void = { _ in }
    var onSettled: (Request, _ changed: Bool) -> Void = { _, _ in }
    var onIdle: () -> Void = {}
    var onFailure: (String) -> Void = { _ in }
    private(set) var requested: Request?
    private(set) var isRunning = false
    private var gesture = false
    private var gestureEnded = true
    private var gestureProgress = 0.0

    func request(_ target: Request) {
        requested = target
        gestureEnded = true
        start()
    }

    func beginGesture(_ target: Request) {
        guard !isRunning else { return }
        requested = target
        gesture = true
        gestureEnded = false
        gestureProgress = 0
        start()
    }

    func scrub(_ value: Double) { gestureProgress = min(1, max(0, value)) }

    func endGesture(commit: Bool) {
        gestureEnded = true
        if !commit { requested = nil }
    }

    func stop() {
        requested = nil
        gestureEnded = true
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor in
            defer { self.isRunning = false; self.gesture = false; self.onIdle() }
            do {
                while let target = self.requested {
                    try await self.transition(target)
                    if self.requested == target { self.requested = nil }
                }
            } catch {
                self.requested = nil
                self.onFailure(error.localizedDescription)
            }
        }
    }

    @MainActor private func transition(_ target: Request) async throws {
        guard let screen = Screen.all().first(where: { $0.uuid == target.display }) else {
            throw DesktopTransitionError.check("The display disconnected")
        }
        let source = Spaces.current(display: target.display)
        Log.info("native workspaces: \(source) → \(target.space), workspace \(target.workspace)")
        if source == target.space { onSettled(target, false); return }
        let busy = "Finish the current macOS Desktop action, then try again"
        try check(!DesktopUI.isBusy(on: screen), busy)
        if let info = Spaces.list(display: target.display), let current = info.current,
           !info.desktops.contains(current) {
            try await leaveNativeFullscreen(target)
            if Spaces.current(display: target.display) == target.space { onSettled(target, true) }
            return
        }
        guard let list = Spaces.list(display: target.display),
              let from = list.ids.firstIndex(of: source), let into = list.ids.firstIndex(of: target.space),
              list.desktops.contains(from), list.desktops.contains(into),
              DesktopUI.isSettled(screen),
              let sourceState = DesktopBridge.state(source), sourceState.transform == .identity,
              let targetState = DesktopBridge.state(target.space), targetState.transform == .identity else {
            throw DesktopTransitionError.check(busy)
        }
        let state = DesktopGuard.Context(display: target.display, source: source, destination: target.space,
                                         sourceOptions: sourceState.options, destinationOptions: targetState.options)
        let recovery = DesktopGuardClient.acquire()
        try await prepareWhileGuarding(target, state, recovery)
        if requested != target { try await recovery.finish(); return }
        var failure: Error?
        do {
            try await compose(state, screen: screen, forward: into > from, target: target, recovery: recovery)
        } catch { failure = error }
        state.restore()
        let restored = await poll(1) {
            DesktopBridge.isIdentity(source) && DesktopBridge.isIdentity(target.space)
                && DesktopBridge.isIdle(display: target.display)
        }
        guard restored else { throw DesktopTransitionError.check("Desktop recovery is still in progress") }
        try await recovery.finish()
        DesktopGuardClient.prewarm()
        if let failure { throw failure }
        Log.info("native workspaces: restored transforms after \(target.workspace)")
        if Spaces.current(display: target.display) == target.space { onSettled(target, true) }
    }

    @MainActor private func prepareWhileGuarding(_ target: Request, _ state: DesktopGuard.Context,
                                                 _ recovery: DesktopGuardClient) async throws {
        let launch = Task { @MainActor in try await recovery.start(state) }
        var preparation: Error?
        do { try await prepare(target) } catch { preparation = error }
        do { try await launch.value } catch { throw preparation ?? error }
        if let preparation { try? await recovery.finish(); throw preparation }
    }

    @MainActor private func compose(_ state: DesktopGuard.Context, screen: Screen, forward: Bool,
                                    target: Request, recovery: DesktopGuardClient) async throws {
        let width = screen.frame.width * (forward ? 1 : -1)
        var progress = 0.0
        try check(DesktopBridge.animating(display: state.display, active: true), "Cannot begin Desktop motion")
        try apply(state, width: width, progress: 0)
        try check(DesktopBridge.willSwitch([state.destination]), "Cannot prepare the destination Desktop")
        try check(DesktopBridge.setVisible([state.destination], true), "Cannot show the destination Desktop")
        let motion = DesktopMotion(screen: screen.nsScreen)
        if gesture {
            try await motion.follow(until: { self.gestureEnded }, update: {
                try self.check(recovery.process.isRunning, "Desktop recovery process stopped")
                progress = self.gestureProgress
                try self.apply(state, width: width, progress: progress)
            })
            gesture = false
        }
        while true {
            let landing = requested == target ? 1.0 : 0.0
            do {
                try await motion.animate(from: progress, to: landing, with: settings) { value in
                    guard (self.requested == target ? 1.0 : 0.0) == landing else { throw Retarget.changed }
                    try self.check(recovery.process.isRunning, "Desktop recovery process stopped")
                    progress = value
                    try self.apply(state, width: width, progress: value)
                }
                break
            } catch Retarget.changed { continue }
        }
        try check(Spaces.current(display: state.display) == state.source,
                  "Native navigation interrupted Desktop motion")
        if requested == target {
            try check(DesktopBridge.setVisible([state.source], false), "Cannot hide the source Desktop")
            try check(DesktopBridge.setCurrent(display: state.display, space: state.destination),
                      "Cannot activate the destination Desktop")
            let arrived = await poll(1) { Spaces.current(display: state.display) == state.destination }
            try check(arrived, "macOS did not activate the destination Desktop")
        }
    }

    private enum Retarget: Error { case changed }

    private func apply(_ state: DesktopGuard.Context, width: CGFloat, progress: Double) throws {
        let pose = min(1, max(0, progress))
        try check(DesktopBridge.transform(state.destination, x: (pose - 1) * width,
                                          options: state.destinationOptions), "Cannot move the destination Desktop")
        try check(DesktopBridge.transform(state.source, x: pose * width, options: state.sourceOptions),
                  "Cannot move the source Desktop")
    }

    @MainActor private func leaveNativeFullscreen(_ target: Request) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func remaining() -> TimeInterval { deadline - ProcessInfo.processInfo.systemUptime }
        while Spaces.current(display: target.display) != target.space {
            if requested != target { return }
            guard remaining() > 0,
                  let list = Spaces.list(display: target.display), let current = list.current,
                  let destination = list.ids.firstIndex(of: target.space) else {
                throw DesktopTransitionError.check("macOS did not leave the maximised window")
            }
            let source = list.ids[current]
            try check(DesktopSwipe.post(right: destination > current), "Native Desktop navigation is unavailable")
            try await check(poll(remaining(), every: 20_000_000) { Spaces.current(display: target.display) != source },
                            "macOS did not change Desktop")
            try await check(poll(remaining(), every: 20_000_000) { DesktopBridge.isIdle(display: target.display) },
                            "macOS did not finish changing Desktop")
        }
    }

    private func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw DesktopTransitionError.check(message) }
    }
}
