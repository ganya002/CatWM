import AppKit
@testable import CatWM
@testable import CatWMKit

final class FakeBackend: WindowBackend {
    struct FakeWindow {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        var frame: CGRect
        var title: String?
        var minSize: CGSize
        var resizable: Bool
        var minimized = false
    }

    enum Write: Equatable {
        case position(CGWindowID, CGPoint)
        case size(CGWindowID, CGSize)

        var id: CGWindowID {
            switch self {
            case let .position(id, _), let .size(id, _): id
            }
        }
    }

    private let lock = NSLock()
    private var screenList: [Screen] = []
    private var apps: [pid_t: String?] = [:]
    private var windowList: [CGWindowID: FakeWindow] = [:]
    private var stacking: [CGWindowID] = []
    private var focusedIn: [pid_t: CGWindowID] = [:]
    private var front: pid_t?
    private var writeLog: [Write] = []
    private var cursorRefreshCount = 0
    private var placementCheckCount = 0
    private var onCursorRefresh: (() -> Void)?
    private var nextID: CGWindowID = 1
    private var nextDisplay: CGDirectDisplayID = 1
    private var scanGate: DispatchSemaphore?

    @discardableResult
    func addScreen(frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900), visible: CGRect? = nil) -> Screen {
        lock.withLock {
            let screen = Screen(id: nextDisplay, uuid: "fake-display-\(nextDisplay)", frame: frame,
                                visible: visible ?? frame, isBuiltin: false, nsScreen: nil)
            nextDisplay += 1
            screenList.append(screen)
            return screen
        }
    }

    func removeScreen(_ screen: Screen) {
        lock.withLock { screenList.removeAll { $0.uuid == screen.uuid } }
    }

    @discardableResult
    func addWindow(pid: pid_t = -100, bundleID: String? = "test.fake.app",
                   frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600), title: String? = "Window",
                   minSize: CGSize = .zero, resizable: Bool = true) -> CGWindowID {
        precondition(pid < 0, "A fake app uses a negative pid, so no AX call reaches a real app")
        return lock.withLock {
            let id = nextID
            nextID += 1
            apps[pid] = apps[pid] ?? bundleID
            windowList[id] = FakeWindow(id: id, pid: pid, element: AXUIElementCreateApplication(-Int32(id)),
                                        frame: frame, title: title, minSize: minSize, resizable: resizable)
            stacking.insert(id, at: 0)
            focusedIn[pid] = id
            front = pid
            return id
        }
    }

    func close(_ id: CGWindowID) {
        lock.withLock {
            guard let closed = windowList.removeValue(forKey: id) else { return }
            stacking.removeAll { $0 == id }
            if focusedIn[closed.pid] == id {
                focusedIn[closed.pid] = stacking.first { windowList[$0]?.pid == closed.pid }
            }
        }
    }

    func close(_ window: Window) -> String {
        close(window.id)
        return "pressed"
    }

    func quit(_ pid: pid_t) {
        lock.withLock {
            let gone = windowList.values.filter { $0.pid == pid }.map(\.id)
            gone.forEach { windowList[$0] = nil }
            stacking.removeAll { gone.contains($0) }
            apps[pid] = nil
            focusedIn[pid] = nil
            if front == pid { front = stacking.first.flatMap { windowList[$0]?.pid } }
        }
    }

    func minimize(_ id: CGWindowID, _ minimized: Bool = true) {
        lock.withLock { windowList[id]?.minimized = minimized }
    }

    func userFocuses(_ id: CGWindowID) {
        lock.withLock {
            guard let window = windowList[id] else { return }
            front = window.pid
            focusedIn[window.pid] = id
            stacking.removeAll { $0 == id }
            stacking.insert(id, at: 0)
        }
    }

    func setResizable(_ id: CGWindowID, _ resizable: Bool) {
        lock.withLock { windowList[id]?.resizable = resizable }
    }

    func setTitle(_ id: CGWindowID, _ title: String?) {
        lock.withLock { windowList[id]?.title = title }
    }

    func userMoves(_ id: CGWindowID, to frame: CGRect) {
        lock.withLock { windowList[id]?.frame = frame }
    }

    func element(_ id: CGWindowID) -> AXUIElement? { lock.withLock { windowList[id]?.element } }

    func frame(of id: CGWindowID) -> CGRect { lock.withLock { windowList[id]?.frame ?? .null } }

    var ids: Set<CGWindowID> { lock.withLock { Set(windowList.keys) } }

    var writes: [Write] { lock.withLock { writeLog } }

    var placementChecks: Int { lock.withLock { placementCheckCount } }

    func clearWrites() { lock.withLock { writeLog = [] } }

    func focused(in pid: pid_t) -> CGWindowID? { lock.withLock { focusedIn[pid] } }

    var frontmost: pid_t? { lock.withLock { front } }

    var cursorRefreshes: Int { lock.withLock { cursorRefreshCount } }

    func holdScans() -> DispatchSemaphore {
        lock.withLock {
            let gate = DispatchSemaphore(value: 0)
            scanGate = gate
            return gate
        }
    }

    func applications() -> [RunningApplicationSnapshot] {
        lock.withLock {
            apps.map { RunningApplicationSnapshot(pid: $0.key, bundleID: $0.value, regular: true, hidden: false) }
        }
    }

    func desktop(known _: Set<CGWindowID>) -> WindowServerObservation {
        lock.withLock {
            let all = stacking.compactMap { windowList[$0] }
            let shown = all.filter { !$0.minimized }
            return WindowServerObservation(
                windows: shown.map { CGWindowInfo(id: $0.id, pid: $0.pid, bounds: $0.frame) },
                allWindows: all.map { CGWindowInfo(id: $0.id, pid: $0.pid, bounds: $0.frame) })
        }
    }

    func scan(_ job: WindowScanner.Job, discovered _: (WindowScanner.AppScan) -> Void) -> WindowScanner.AppScan {
        if let gate = lock.withLock({ scanGate }) {
            gate.wait()
            gate.signal()
        }
        return lock.withLock {
            var scan = WindowScanner.AppScan()
            let mine = stacking.compactMap { windowList[$0] }.filter { $0.pid == job.pid }
            if job.listWindows { scan.listed = mine.map(\.id) }
            for window in mine where job.listWindows || job.known[window.id] != nil {
                if window.minimized { scan.minimized.insert(window.id) }
                guard !window.minimized || job.known[window.id] != nil else { continue }
                scan.found[window.id] = .init(element: window.element, frame: window.frame, title: window.title,
                                              resizable: window.resizable,
                                              frameRevision: job.known[window.id]?.frameRevision)
            }
            scan.gone = Set(job.known.keys).subtracting(mine.map(\.id))
            return scan
        }
    }

    func focusedWindow(pid: pid_t) -> FocusReader.Result { lock.withLock { .focused(focusedIn[pid]) } }

    func screens() -> [Screen] { lock.withLock { screenList } }

    func currentSpace(display _: String) -> UInt64 { 1 }

    func isRunning(_ pid: pid_t) -> Bool { lock.withLock { apps[pid] != nil } }

    func frontmostPID() -> pid_t? { lock.withLock { front } }

    func frame(of window: Window) -> CGRect { frame(of: window.id) }

    func setPosition(_ window: Window, _ point: CGPoint) -> Bool {
        lock.withLock {
            guard windowList[window.id] != nil else { return false }
            windowList[window.id]?.frame.origin = point
            writeLog.append(.position(window.id, point))
            return true
        }
    }

    func setSize(_ window: Window, _ size: CGSize) -> Bool {
        lock.withLock {
            guard let fake = windowList[window.id], fake.resizable else { return false }
            windowList[window.id]?.frame.size = CGSize(width: max(size.width, fake.minSize.width),
                                                       height: max(size.height, fake.minSize.height))
            writeLog.append(.size(window.id, size))
            return true
        }
    }

    func blocksPlacement(_ window: Window) -> Bool {
        lock.withLock {
            placementCheckCount += 1
            return windowList[window.id]?.minimized ?? true
        }
    }

    func suspendEnhancedUI(_: pid_t) -> Bool { false }

    func resumeEnhancedUI(_: pid_t) {}

    func focus(_ window: Window, ifCurrent: () -> Bool) {
        guard ifCurrent() else { return }
        userFocuses(window.id)
    }

    func refreshCursor() {
        let observer = lock.withLock {
            cursorRefreshCount += 1
            return onCursorRefresh
        }
        observer?()
    }

    func observeCursorRefresh(_ observer: (() -> Void)?) { lock.withLock { onCursorRefresh = observer } }
}

extension FakeBackend {
    private static let defaults = Config.parse(defaultText)

    @MainActor func makeManager(_ configure: (inout Config) -> Void = { _ in }) -> WindowManager {
        var config = Self.defaults
        config.virtualWorkspaces = false
        config.animate = false
        config.mouseFollowsFocus = false
        config.focusFollowsMouse = false
        config.windowMargins = false
        config.paddingLeft = 0; config.paddingRight = 0; config.paddingTop = 0; config.paddingBottom = 0
        configure(&config)
        let manager = WindowManager(backend: self, config: config)
        manager.startEngine()
        return manager
    }

    @MainActor @discardableResult
    func settle(_ manager: WindowManager, rounds: Int = 8, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        for _ in 0..<rounds {
            let before = writes.count
            let scanned = await bounded(until: deadline) { waiter in
                manager.scanAndRefresh { waiter.finish(true) }
                let request = manager.scanRequests
                return { manager.scanWaiters.removeAll { $0.request == request } }
            }
            guard scanned, await bounded(until: deadline, { waiter in
                manager.animator.afterPendingWrites { waiter.finish(true) }
                return {}
            }) else { return false }
            if writes.count == before, Set(manager.windows.keys) == ids { return true }
        }
        return false
    }

    @MainActor @discardableResult
    func wait(_ manager: WindowManager, timeout: TimeInterval = 10,
              until condition: @escaping () -> Bool) async -> Bool {
        guard !condition() else { return true }
        return await bounded(until: Date().addingTimeInterval(timeout)) { waiter in
            manager.onChange = { if condition() { waiter.finish(true) } }
            self.observeCursorRefresh { if condition() { waiter.finish(true) } }
            return {
                manager.onChange = nil
                self.observeCursorRefresh(nil)
            }
        }
    }

    @MainActor private func bounded(until deadline: Date,
                                    _ start: @escaping (Waiter) -> () -> Void) async -> Bool {
        let waiter = Waiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { done in
                waiter.start(done, until: deadline, start)
                if Task.isCancelled { waiter.finish(false) }
            }
        } onCancel: {
            Task { @MainActor in waiter.finish(false) }
        }
    }

    @MainActor private final class Waiter {
        private var done: CheckedContinuation<Bool, Never>?
        private var deadline: DispatchWorkItem?
        private var cleanUp: (() -> Void)?

        func start(_ done: CheckedContinuation<Bool, Never>, until end: Date, _ start: (Waiter) -> () -> Void) {
            self.done = done
            let deadline = DispatchWorkItem { [weak self] in self?.finish(false) }
            self.deadline = deadline
            DispatchQueue.main.asyncAfter( // style-ok: deadline of a wait
                deadline: .now() + max(end.timeIntervalSinceNow, 0), execute: deadline)
            let cleanUp = start(self)
            if self.done == nil { cleanUp() } else { self.cleanUp = cleanUp }
        }

        func finish(_ met: Bool) {
            guard let done else { return }
            self.done = nil
            deadline?.cancel()
            cleanUp?()
            cleanUp = nil
            done.resume(returning: met)
        }
    }
}
