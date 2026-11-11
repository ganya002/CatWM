import Foundation
import os

package final class PendingWrites: Sendable {
    private struct State: Sendable {
        package var continuation: CheckedContinuation<Bool, Never>?
        package var result: Result<Bool, Never>?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    package func wait(_ continuation: CheckedContinuation<Bool, Never>) {
        let result = state.withLock { state -> Result<Bool, Never>? in
            if state.result == nil { state.continuation = continuation }
            return state.result
        }
        if let result { continuation.resume(with: result) }
    }

    package func finish(_ result: Bool) {
        let waiting = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            guard state.result == nil else { return nil }
            state.result = .success(result)
            defer { state.continuation = nil }
            return state.continuation
        }
        waiting?.resume(returning: result)
    }
}

extension Animator {
    @MainActor func waitForPendingWrites(pids: Set<pid_t>, timeout: TimeInterval = 1) async -> Bool {
        let completion = PendingWrites()
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return } // style-ok: a hung app never drains
            completion.finish(false)
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                completion.wait(continuation)
                afterPendingWrites(pids: pids) { completion.finish(true) }
            }
        } onCancel: {
            completion.finish(false)
        }
    }
}
