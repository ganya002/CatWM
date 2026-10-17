import Foundation

enum TemplateSlotOutcome<Value: Sendable>: Sendable {
    case finished(Value)
    case timedOut
    case cancelled
    case busy
}

extension TemplateSlotOutcome: Equatable where Value: Equatable {
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

final class TemplateStopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    func stop() { lock.withLock { stopped = true } }
    var isStopped: Bool { lock.withLock { stopped } }
}

final class TemplateCaptureSlot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var active: Task<Value, Never>?
    private var activeID = 0

    var isIdle: Bool { lock.withLock { active == nil } }

    func run(within timeout: Duration, operation: @escaping @Sendable () async -> Value) async -> TemplateSlotOutcome<Value> {
        guard let task = claim(operation) else { return .busy }
        return await race(task, timeout: timeout)
    }

    private func claim(_ operation: @escaping @Sendable () async -> Value) -> Task<Value, Never>? {
        lock.lock()
        if active != nil {
            lock.unlock()
            return nil
        }
        activeID += 1
        let id = activeID
        let created = Task { [weak self] in
            let value = await operation()
            self?.clear(id)
            return value
        }
        active = created
        lock.unlock()
        return created
    }

    private func clear(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard activeID == id else { return }
        active = nil
    }

    private func race(_ task: Task<Value, Never>, timeout: Duration) async -> TemplateSlotOutcome<Value> {
        let gate = OnceGate<TemplateSlotOutcome<Value>>()
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

private final class OnceGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var pending: T?
    private var done = false

    func install(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        if let pending {
            lock.unlock()
            continuation.resume(returning: pending)
            return
        }
        if done {
            lock.unlock()
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    @discardableResult
    func resume(_ value: T) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        done = true
        let continuation = continuation
        self.continuation = nil
        if continuation == nil { pending = value }
        lock.unlock()
        continuation?.resume(returning: value)
        return true
    }
}
