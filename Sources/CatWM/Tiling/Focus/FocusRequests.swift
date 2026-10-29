import CoreGraphics
import Foundation

struct FocusRequests {
    struct PendingFocus {
        let id: CGWindowID
        let pid: pid_t
        let origin: pid_t?
        let request: UUID
        var executed = false
    }

    struct FocusCommand {
        let pid: pid_t
        let dispatcher: String
        let arg: String
        let inMode: Bool
    }

    struct Observation {
        let generation: Int
        let shouldRead: Bool
        let cancelledRequest: Bool
    }

    enum PendingWindow { case none, window(CGWindowID), cancelled }

    private(set) var pendingFocus: PendingFocus?
    private(set) var focusCommands: [FocusCommand] = []
    private(set) var waitingRefocus: (workspace: String, pid: pid_t)?
    private var refocusAfterClose: String?
    var focusEcho: FocusEcho?
    private(set) var reportedFocus: (pid: pid_t, id: CGWindowID?)?
    var focusReader = FocusReader()
    private(set) var focusObservation = 0
    private(set) var focusReads: Set<pid_t> = []
    var retryRead: (@escaping () -> Void) -> Void = { read in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: read) // style-ok: a busy app sends no AX event
    }

    var needsObservation: Bool {
        !focusCommands.isEmpty || waitingRefocus != nil || pendingFocus?.executed == true
    }

    @discardableResult
    mutating func begin(id: CGWindowID, pid: pid_t, origin: pid_t?) -> UUID {
        let request = UUID()
        pendingFocus = PendingFocus(id: id, pid: pid, origin: origin, request: request)
        return request
    }

    mutating func executed(_ request: UUID) -> Bool {
        guard pendingFocus?.request == request else { return false }
        pendingFocus?.executed = true
        return true
    }

    mutating func beginObservation(pid: pid_t) -> Observation {
        if reportedFocus?.pid != pid { reportedFocus = nil }
        focusCommands.removeAll { $0.pid != pid }
        if let waiting = waitingRefocus, waiting.pid != pid { waitingRefocus = nil }
        let cancelled = pendingFocus.map { $0.pid != pid && $0.origin != pid } ?? false
        if cancelled { cancel() }
        invalidateObservation()
        return Observation(generation: focusObservation, shouldRead: focusReads.insert(pid).inserted,
                           cancelledRequest: cancelled)
    }

    mutating func finishObservation(pid: pid_t, generation: Int) -> Bool {
        focusReads.remove(pid)
        return isCurrent(generation)
    }

    func isCurrent(_ generation: Int) -> Bool { focusObservation == generation }

    mutating func invalidateObservation() { focusObservation += 1 }

    mutating func report(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool = false) {
        reportedFocus = (pid, id)
        if confirmsRequest, pendingFocus?.executed == true { pendingFocus = nil }
    }

    mutating func confirm(_ id: CGWindowID) -> Bool {
        guard let pending = pendingFocus else { return true }
        guard pending.id == id else { return false }
        if pending.executed { pendingFocus = nil }
        return true
    }

    mutating func enqueue(_ command: FocusCommand) { focusCommands.append(command) }

    mutating func takeCommands() -> [FocusCommand] {
        let commands = focusCommands
        focusCommands = []
        return commands
    }

    mutating func waitToRefocus(on workspace: String, pid: pid_t) { waitingRefocus = (workspace, pid) }

    mutating func takeWaitingRefocus() -> (workspace: String, pid: pid_t)? {
        let waiting = waitingRefocus
        waitingRefocus = nil
        return waiting
    }

    mutating func takeRefocusAfterClose() -> String? {
        let workspace = refocusAfterClose
        refocusAfterClose = nil
        return workspace
    }

    mutating func forget(_ id: CGWindowID, refocusOn workspace: String?) -> Bool {
        if let workspace { refocusAfterClose = workspace }
        let cancelled = pendingFocus?.id == id
        if cancelled { cancel() }
        if reportedFocus?.id == id {
            reportedFocus = nil
            invalidateObservation()
        }
        return cancelled
    }

    mutating func resolvePending(frontmost pid: pid_t?, available: (CGWindowID) -> Bool) -> PendingWindow {
        guard let pending = pendingFocus else { return .none }
        if pid == pending.pid || pid == pending.origin, available(pending.id) { return .window(pending.id) }
        cancel()
        return .cancelled
    }

    mutating func cancel() {
        pendingFocus = nil
        focusCommands = []
        waitingRefocus = nil
        invalidateObservation()
    }
}
