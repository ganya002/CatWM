import Foundation
import os

package final class ScopeLifetime: Sendable {
    private struct State {
        var remaining: Set<pid_t>
        var fired = false
        var watches: [DispatchSourceProcess] = []
    }

    private let pids: Set<pid_t>
    private let alive: @Sendable (pid_t) -> Bool
    private let ended: @Sendable () -> Void
    private let state: OSAllocatedUnfairLock<State>

    package init(pids: Set<pid_t>, alive: @escaping @Sendable (pid_t) -> Bool = ScopeLifetime.isAlive,
                 ended: @escaping @Sendable () -> Void) {
        self.pids = pids
        self.alive = alive
        self.ended = ended
        state = OSAllocatedUnfairLock(initialState: State(remaining: pids))
    }

    deinit { stop() }

    package func start() {
        let watches = pids.map { pid in
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit,
                                                          queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in self?.exited(pid) }
            source.resume()
            return source
        }
        state.withLock { $0.watches = watches }
        for pid in pids where !alive(pid) { exited(pid) }
    }

    package func stop() {
        state.withLock { state in
            state.watches.forEach { $0.cancel() }
            state.watches = []
        }
    }

    package static let isAlive: @Sendable (pid_t) -> Bool = { pid in
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return size > 0 && info.pbi_status != UInt32(SZOMB)
    }

    private func exited(_ pid: pid_t) {
        let last = state.withLock { state in
            state.remaining.remove(pid)
            guard state.remaining.isEmpty, !state.fired else { return false }
            state.fired = true
            return true
        }
        if last { ended() }
    }
}
