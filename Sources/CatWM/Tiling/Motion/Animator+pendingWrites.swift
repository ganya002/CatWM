import Foundation

extension Animator {
    @MainActor func waitForPendingWrites(pids: Set<pid_t>, timeout: TimeInterval = 1) async -> Bool {
        let completion = PendingWrites()
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            completion.finish(false)
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                completion.wait(continuation)
                afterPendingWrites(pids: pids) {
                    MainActor.assumeIsolated { completion.finish(true) }
                }
            }
        } onCancel: {
            Task { @MainActor in completion.finish(false) }
        }
    }

    @MainActor private final class PendingWrites {
        private var continuation: CheckedContinuation<Bool, Never>?
        private var result: Result<Bool, Never>?

        func wait(_ continuation: CheckedContinuation<Bool, Never>) {
            if let result { continuation.resume(with: result) } else { self.continuation = continuation }
        }

        func finish(_ result: Bool) {
            guard self.result == nil else { return }
            self.result = .success(result)
            continuation?.resume(returning: result)
            continuation = nil
        }
    }
}
