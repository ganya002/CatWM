import Foundation
import os

enum SlotOutcome<Value: Sendable>: Sendable {
    case finished(Value)
    case timedOut
    case cancelled
    case busy
}

extension SlotOutcome: Equatable where Value: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
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

final class StopFlag: Sendable {
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    init() {}

    func stop() { stopped.withLock { $0 = true } }
    var isStopped: Bool { stopped.withLock { $0 } }
}

final class CaptureSlot<Value: Sendable>: Sendable {
    private let state = OSAllocatedUnfairLock<(active: Task<Value, Never>?, activeID: Int)>(initialState: (nil, 0))

    init() {}

    var isIdle: Bool { state.withLock { $0.active == nil } }

    func run(within timeout: Duration,
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
        var continuation: CheckedContinuation<T, Never>?
        var pending: T?
        var done = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<T, Never>) {
        let pending: T? = state.withLock {
            if let pending = $0.pending { return pending }
            if !$0.done { $0.continuation = continuation }
            return nil
        }
        if let pending { continuation.resume(returning: pending) }
    }

    @discardableResult
    func resume(_ value: T) -> Bool {
        let claimed: (Bool, CheckedContinuation<T, Never>?) = state.withLock {
            guard !$0.done else { return (false, nil) }
            $0.done = true
            let continuation = $0.continuation
            $0.continuation = nil
            if continuation == nil { $0.pending = value }
            return (true, continuation)
        }
        claimed.1?.resume(returning: value)
        return claimed.0
    }
}
