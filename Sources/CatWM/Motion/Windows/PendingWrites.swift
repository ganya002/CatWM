import Foundation
import os

final class PendingWrites: Sendable {
    private struct State: Sendable {
        var continuation: CheckedContinuation<Bool, Never>?
        var result: Result<Bool, Never>?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func wait(_ continuation: CheckedContinuation<Bool, Never>) {
        let result = state.withLock { state -> Result<Bool, Never>? in
            if state.result == nil { state.continuation = continuation }
            return state.result
        }
        if let result { continuation.resume(with: result) }
    }

    func finish(_ result: Bool) {
        let waiting = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            guard state.result == nil else { return nil }
            state.result = .success(result)
            defer { state.continuation = nil }
            return state.continuation
        }
        waiting?.resume(returning: result)
    }
}
