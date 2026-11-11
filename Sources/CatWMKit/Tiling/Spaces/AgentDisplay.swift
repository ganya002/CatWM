import AppKit
import ApplicationServices

@MainActor package final class AgentDisplay {
    nonisolated private static let vendor: UInt32 = 0x4341
    nonisolated private static let product: UInt32 = 0x5701

    nonisolated package static func owns(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == vendor && CGDisplayModelNumber(id) == product
    }

    package struct Backing {
        package let id: CGDirectDisplayID
        package let uuid: String
        package var bounds: () -> CGRect = { .zero }
        package var owner: AnyObject?

        package init(id: CGDirectDisplayID, uuid: String, bounds: @escaping () -> CGRect, owner: AnyObject? = nil) {
            (self.id, self.uuid, self.bounds, self.owner) = (id, uuid, bounds, owner)
        }
    }

    package struct Windows {
        package var ids: @MainActor (pid_t) -> [CGWindowID]
        package var bounds: @MainActor (CGWindowID) -> CGRect?
        package var move: @MainActor (pid_t, CGWindowID, CGPoint) -> Bool
        package var watch: @MainActor (pid_t, @escaping @MainActor () -> Void) -> AnyObject?

        @MainActor package static let live = Windows(
            ids: { axApp($0).elements(kAXWindowsAttribute).compactMap(\.windowID) },
            bounds: { id in
                let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
                return (info?.first?[kCGWindowBounds as String] as? [String: Any])
                    .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            },
            move: { pid, id, point in
                var point = point
                guard let window = axApp(pid).elements(kAXWindowsAttribute).first(where: { $0.windowID == id }),
                      let value = AXValueCreate(.cgPoint, &point) else { return false }
                return window.set(kAXPositionAttribute, value)
            },
            watch: { pid, created in AXWindowCreated(pid: pid, created) })
    }

    private final class Poll {
        var deadline: TimeInterval
        var work: @MainActor () -> Void = {}
        init(deadline: TimeInterval) { self.deadline = deadline }
    }

    package enum LaunchError: Error, Equatable {
        case notFound, running, failed
    }

    package let id: CGDirectDisplayID
    package let uuid: String
    package var bounds: CGRect { backing?.bounds() ?? .zero }
    package var pids: Set<pid_t> { Set(watches.keys) }

    private var backing: Backing?
    private let windows: Windows
    private let updates: WindowServerUpdates
    private let paths: InstancePaths
    private let settle: Double
    package typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    private let schedule: Schedule
    private let now: @MainActor () -> TimeInterval
    private var watches: [pid_t: AnyObject?] = [:]
    private var claimed = false
    private var closing = false
    private var polls: [pid_t: Poll] = [:]

    package init?(backing: Backing? = AgentDisplay.makeVirtual(), windows: Windows = .live,
                  updates: WindowServerUpdates = .shared, home: URL = Instance.paths.home, settle: Double = 0.25,
                  now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                  schedule: @escaping Schedule = { delay, work in
                      DispatchQueue.main.asyncAfter( // style-ok: polls the window server, which has no event
                          deadline: .now() + delay, execute: work)
                  }) {
        guard let backing, let paths = InstancePaths(id: "agent-\(backing.id)", home: home) else { return nil }
        (id, uuid, self.backing, self.windows, self.updates, self.paths) = (backing.id, backing.uuid, backing, windows,
                                                                            updates, paths)
        (self.settle, self.now, self.schedule) = (settle, now, schedule)
    }

    deinit {
        if claimed { Self.removeClaim(paths, id) }
    }

    package func close() {
        watches = [:]
        polls = [:]
        publishClaim()
        backing = nil
    }

    @MainActor
    package func launch(_ bundleID: String, arguments: [String] = []) async throws -> pid_t {
        guard backing != nil, !closing else { throw LaunchError.failed }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw LaunchError.notFound
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
            !watches.keys.contains($0.processIdentifier)
        }) else {
            Log.info("agent display: \(bundleID) already runs, so its windows stay where they are")
            throw LaunchError.running
        }
        guard let app = await Launcher.start(.app(url), activates: false, arguments: arguments) else {
            Log.info("agent display: \(bundleID) did not open")
            throw LaunchError.failed
        }
        guard backing != nil, !closing else {
            app.terminate()
            throw LaunchError.failed
        }
        claim(app.processIdentifier)
        return app.processIdentifier
    }

    @MainActor
    package func quit(grace: TimeInterval = 3) async {
        closing = true
        let apps = watches.keys.compactMap(NSRunningApplication.init(processIdentifier:))
        apps.forEach { $0.terminate() }
        for app in apps { await exit(of: app, grace: grace) }
        close()
    }

    @MainActor
    private func exit(of app: NSRunningApplication, grace: TimeInterval) async {
        guard !app.isTerminated else { return }
        let wait = ExitWait()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            wait.done = done
            wait.token = app.observe(\.isTerminated, options: [.initial]) { [wait] app, _ in
                guard app.isTerminated else { return }
                DispatchQueue.main.async { wait.finish() }
            }
            schedule(grace) { if !app.isTerminated { app.forceTerminate() } }
        }
    }

    package func windowIDs() -> [(pid: pid_t, id: CGWindowID)] {
        let target = bounds
        return watches.keys.sorted().flatMap { pid in
            windows.ids(pid).filter { window in
                windows.bounds(window).map { target.contains($0.center) } ?? false
            }.map { (pid, $0) }
        }
    }

    package func frame(of window: CGWindowID) -> CGRect? { windows.bounds(window) }

    package func claim(_ pid: pid_t) {
        guard backing != nil, pid > 0, !watches.keys.contains(pid) else { return }
        watches[pid] = .some(nil)
        publishClaim()
        watches[pid] = .some(windows.watch(pid) { [weak self] in self?.sweep(pid) })
        sweep(pid)
    }

    package func sweep(_ pid: pid_t) {
        let target = bounds
        guard !target.isEmpty else { return }
        if let poll = polls[pid] {
            poll.deadline = now() + settle
            poll.work()
            return
        }
        let poll = Poll(deadline: now() + settle)
        polls[pid] = poll
        var lease: WindowServerUpdates.Lease?
        var began = now()
        poll.work = { @MainActor [weak self, weak poll] in
            guard let self, let poll else { return }
            @MainActor func strays() -> [CGWindowID] {
                self.windows.ids(pid).filter { id in
                    !(self.windows.bounds(id).map { target.contains($0.center) } ?? false)
                }
            }
            var outside = strays()
            if !outside.isEmpty {
                if lease == nil {
                    lease = self.updates.begin()
                    began = self.now()
                }
                for window in outside { _ = self.windows.move(pid, window, target.origin) }
                outside = strays()
            }
            let remaining = poll.deadline - self.now()
            if outside.isEmpty || remaining <= 0, let held = lease {
                Log.info(String(format: "agent display: pid %d settled in %.0f ms, %d window(s) still outside", pid,
                                (self.now() - began) * 1000, outside.count))
                held.finish()
                lease = nil
            }
            if remaining <= 0 { self.polls[pid] = nil }
        }
        pump(poll, pid)
    }

    private func pump(_ poll: Poll, _ pid: pid_t) {
        poll.work()
        let remaining = poll.deadline - now()
        guard remaining > 0, polls[pid] === poll else { return }
        schedule(min(0.004, remaining)) { [weak self, weak poll] in
            if let self, let poll { self.pump(poll, pid) }
        }
    }

    private func publishClaim() {
        let pids = Set(watches.keys)
        Log.attempt("write the claim of display \(id)") {
            if !pids.isEmpty {
                try paths.writeClaim(ScopeClaim(owner: getpid(), scope: WindowScope(pids: pids, display: uuid)))
            } else if claimed {
                Self.removeClaim(paths, id)
            }
        }
        claimed = !pids.isEmpty
    }

    nonisolated private static func removeClaim(_ paths: InstancePaths, _ id: CGDirectDisplayID) {
        Log.attempt("remove the claim of display \(id)") {
            try paths.removeClaim()
            try FileManager.default.removeItem(at: paths.configFolder)
        }
    }
}

@MainActor private final class ExitWait {
    var token: NSKeyValueObservation?
    var done: CheckedContinuation<Void, Never>?

    func finish() {
        token?.invalidate()
        token = nil
        done?.resume()
        done = nil
    }
}

@MainActor private final class AXWindowCreated {
    private let pid: pid_t
    private let created: @MainActor () -> Void
    private var observer: AXReference<AXObserver>?
    private var attempts = 0

    init(pid: pid_t, _ created: @escaping @MainActor () -> Void) {
        (self.pid, self.created) = (pid, created)
        register()
    }

    deinit {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.object), .defaultMode)
    }

    private func register() {
        attempts += 1
        var made: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let watch = Unmanaged<AXWindowCreated>.fromOpaque(refcon).takeUnretainedValue()
            let (element, isNew) = (AXReference(element), notification as String == kAXWindowCreatedNotification)
            onMainThread {
                if isNew { watch.follow(element.object) }
                watch.created()
            }
        }
        guard AXObserverCreate(pid, callback, &made) == .success, let made,
              AXObserverAddNotification(made, axApp(pid), kAXWindowCreatedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else {
            guard attempts < 1000, kill(pid, 0) == 0 else {
                Log.info("agent display: cannot observe the windows of pid \(pid)")
                return
            }
            DispatchQueue.main.asyncAfter( // style-ok: a new process answers AX only after its launch, with no event
                deadline: .now() + 0.01
            ) { [weak self] in self?.register() }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .defaultMode)
        observer = AXReference(made)
        axApp(pid).elements(kAXWindowsAttribute).forEach(follow)
        created()
    }

    private func follow(_ window: AXUIElement) {
        guard let observer else { return }
        AXObserverAddNotification(observer.object, window, kAXMovedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }
}

extension AgentDisplay {
    private typealias ObjectCall = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
    private typealias ModeCall = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> Unmanaged<AnyObject>?
    private typealias ApplyCall = @convention(c) (AnyObject, Selector, AnyObject) -> Bool

    package static func makeVirtual(width: UInt32 = 1920, height: UInt32 = 1080) -> Backing? {
        func method<T>(_ cls: AnyClass, _ name: String, as _: T.Type) -> (Selector, T)? {
            let selector = NSSelectorFromString(name)
            return class_getMethodImplementation(cls, selector).map { (selector, unsafeBitCast($0, to: T.self)) }
        }
        func allocate(_ cls: AnyClass) -> AnyObject? {
            (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        }
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let displayClass = NSClassFromString("CGVirtualDisplay"),
              let (modeSelector, modeInit) = method(modeClass, "initWithWidth:height:refreshRate:", as: ModeCall.self),
              let (initSelector, displayInit) = method(displayClass, "initWithDescriptor:", as: ObjectCall.self),
              let (applySelector, apply) = method(displayClass, "applySettings:", as: ApplyCall.self),
              let rawMode = allocate(modeClass), let rawDisplay = allocate(displayClass),
              let mode = modeInit(rawMode, modeSelector, width, height, 60)?.takeRetainedValue()
        else {
            Log.info("agent display: the private display classes are missing")
            return nil
        }
        let descriptor = descriptorClass.init()
        descriptor.setValuesForKeys(["queue": DispatchQueue.main, "name": "CatWM agent display", "maxPixelsWide": width,
                                     "maxPixelsHigh": height, "vendorID": vendor, "productID": product,
                                     "serialNum": 1,
                                     "sizeInMillimeters": NSValue(size: NSSize(width: 527, height: 296))])
        let settings = settingsClass.init()
        settings.setValuesForKeys(["hiDPI": 0, "modes": [mode]])
        guard let display = displayInit(rawDisplay, initSelector, descriptor)?.takeRetainedValue() as? NSObject,
              apply(display, applySelector, settings), let id = display.value(forKey: "displayID") as? UInt32 else {
            Log.info("agent display: the virtual display was refused")
            return nil
        }
        let deadline = Date().addingTimeInterval(2)
        func uuid() -> String? {
            CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        }
        while CGDisplayBounds(id).isEmpty || uuid() == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        guard !CGDisplayBounds(id).isEmpty, let text = uuid() else {
            Log.info("agent display: display \(id) never came online")
            return nil
        }
        return Backing(id: id, uuid: text, bounds: { CGDisplayBounds(id) }, owner: display)
    }
}
