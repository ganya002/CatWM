import Foundation
import os

package enum SlotOutcome<Value: Sendable>: Sendable {
    case finished(Value)
    case timedOut
    case cancelled
    case busy
}

extension SlotOutcome: Equatable where Value: Equatable {
    package static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.timedOut, .timedOut), (.cancelled, .cancelled), (.busy, .busy):
            return true
        case (.finished(let left), .finished(let right)):
            return left == right
        default:
            return false
        }
    }
}

package final class StopFlag: Sendable {
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    package init() {}

    package func stop() { stopped.withLock { $0 = true } }
    package var isStopped: Bool { stopped.withLock { $0 } }
}

package final class CaptureSlot<Value: Sendable>: Sendable {
    private struct State: Sendable {
        package var active: Task<Value, Never>?
        package var activeID = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init() {}

    package var isIdle: Bool { state.withLock { $0.active == nil } }

    package func run(within timeout: Duration,
                     operation: @escaping @Sendable () async -> Value) async -> SlotOutcome<Value> {
        guard let task = claim(operation) else { return .busy }
        return await race(task, timeout: timeout)
    }

    private func claim(_ operation: @escaping @Sendable () async -> Value) -> Task<Value, Never>? {
        state.withLock { state in
            guard state.active == nil else { return nil }
            state.activeID += 1
            let id = state.activeID
            let created = Task { [weak self] in
                let value = await operation()
                self?.clear(id)
                return value
            }
            state.active = created
            return created
        }
    }

    private func clear(_ id: Int) {
        state.withLock { state in
            guard state.activeID == id else { return }
            state.active = nil
        }
    }

    private func race(_ task: Task<Value, Never>, timeout: Duration) async -> SlotOutcome<Value> {
        let gate = OnceGate<SlotOutcome<Value>>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    _ = gate.resume(.timedOut)
                }
                Task {
                    let value = await task.value
                    if gate.resume(.finished(value)) { timer.cancel() }
                }
            }
        } onCancel: {
            _ = gate.resume(.cancelled)
        }
    }
}

private final class OnceGate<T: Sendable>: Sendable {
    private struct State: Sendable {
        package var continuation: CheckedContinuation<T, Never>?
        package var pending: T?
        package var done = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    package func install(_ continuation: CheckedContinuation<T, Never>) {
        let pending = state.withLock { state -> T? in
            if let pending = state.pending { return pending }
            if !state.done { state.continuation = continuation }
            return nil
        }
        if let pending { continuation.resume(returning: pending) }
    }

    @discardableResult
    package func resume(_ value: T) -> Bool {
        let (first, continuation) = state.withLock { state -> (Bool, CheckedContinuation<T, Never>?) in
            guard !state.done else { return (false, nil) }
            state.done = true
            let continuation = state.continuation
            state.continuation = nil
            if continuation == nil { state.pending = value }
            return (true, continuation)
        }
        continuation?.resume(returning: value)
        return first
    }
}
