import CoreGraphics
import Foundation

package struct FocusRequests {
    package struct PendingFocus {
        package let id: CGWindowID
        package let pid: pid_t
        package let origin: pid_t?
        package let request: UUID
        package var executed = false
    }

    package struct FocusCommand {
        package let pid: pid_t
        package let dispatcher: String
        package let arg: String
        package let inMode: Bool
    }

    package struct Observation {
        package let generation: Int
        package let shouldRead: Bool
        package let cancelledRequest: Bool
    }

    package enum PendingWindow { case none, window(CGWindowID), cancelled }

    package private(set) var pendingFocus: PendingFocus?
    package private(set) var focusCommands: [FocusCommand] = []
    package private(set) var waitingRefocus: (workspace: String, pid: pid_t)?
    private var refocusAfterClose: String?
    package var focusEcho: FocusEcho?
    package private(set) var reportedFocus: (pid: pid_t, id: CGWindowID?)?
    package var focusReader = FocusReader()
    package private(set) var focusObservation = 0
    package private(set) var focusReads: Set<pid_t> = []
    package var retryRead: (@escaping () -> Void) -> Void = { read in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: read) // style-ok: a busy app sends no AX event
    }

    package var needsObservation: Bool {
        !focusCommands.isEmpty || waitingRefocus != nil || pendingFocus?.executed == true
    }

    @discardableResult
    package mutating func begin(id: CGWindowID, pid: pid_t, origin: pid_t?) -> UUID {
        let request = UUID()
        pendingFocus = PendingFocus(id: id, pid: pid, origin: origin, request: request)
        return request
    }

    package mutating func executed(_ request: UUID) -> Bool {
        guard pendingFocus?.request == request else { return false }
        pendingFocus?.executed = true
        return true
    }

    package mutating func beginObservation(pid: pid_t) -> Observation {
        if reportedFocus?.pid != pid { reportedFocus = nil }
        focusCommands.removeAll { $0.pid != pid }
        if let waiting = waitingRefocus, waiting.pid != pid { waitingRefocus = nil }
        let cancelled = pendingFocus.map { $0.pid != pid && $0.origin != pid } ?? false
        if cancelled { cancel() }
        invalidateObservation()
        return Observation(generation: focusObservation, shouldRead: focusReads.insert(pid).inserted,
                           cancelledRequest: cancelled)
    }

    package mutating func finishObservation(pid: pid_t, generation: Int) -> Bool {
        focusReads.remove(pid)
        return isCurrent(generation)
    }

    package func isCurrent(_ generation: Int) -> Bool { focusObservation == generation }

    package mutating func invalidateObservation() { focusObservation += 1 }

    package mutating func report(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool = false) {
        reportedFocus = (pid, id)
        if confirmsRequest, pendingFocus?.executed == true { pendingFocus = nil }
    }

    package mutating func confirm(_ id: CGWindowID) -> Bool {
        guard let pending = pendingFocus else { return true }
        guard pending.id == id else { return false }
        if pending.executed { pendingFocus = nil }
        return true
    }

    package mutating func enqueue(_ command: FocusCommand) { focusCommands.append(command) }

    package mutating func takeCommands() -> [FocusCommand] {
        let commands = focusCommands
        focusCommands = []
        return commands
    }

    package mutating func waitToRefocus(on workspace: String, pid: pid_t) { waitingRefocus = (workspace, pid) }

    package mutating func takeWaitingRefocus() -> (workspace: String, pid: pid_t)? {
        let waiting = waitingRefocus
        waitingRefocus = nil
        return waiting
    }

    package mutating func takeRefocusAfterClose() -> String? {
        let workspace = refocusAfterClose
        refocusAfterClose = nil
        return workspace
    }

    package mutating func forget(_ id: CGWindowID, refocusOn workspace: String?) -> Bool {
        if let workspace { refocusAfterClose = workspace }
        let cancelled = pendingFocus?.id == id
        if cancelled { cancel() }
        if reportedFocus?.id == id {
            reportedFocus = nil
            invalidateObservation()
        }
        return cancelled
    }

    package mutating func resolvePending(frontmost pid: pid_t?, available: (CGWindowID) -> Bool) -> PendingWindow {
        guard let pending = pendingFocus else { return .none }
        if pid == pending.pid || pid == pending.origin, available(pending.id) { return .window(pending.id) }
        cancel()
        return .cancelled
    }

    package mutating func cancel() {
        pendingFocus = nil
        focusCommands = []
        waitingRefocus = nil
        invalidateObservation()
    }
}
