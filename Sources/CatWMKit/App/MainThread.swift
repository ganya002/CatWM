import Foundation

package func onMainThread<T: Sendable>(_ body: @MainActor () -> T) -> T {
    MainActor.assumeIsolated(body) // style-ok: C callbacks run on the main run loop and need a synchronous answer
}

extension NotificationCenter {
    @discardableResult
    package func observeOnMain(_ name: Notification.Name?, object: Any? = nil,
                               _ handler: @escaping @MainActor () -> Void) -> any NSObjectProtocol {
        addObserver(forName: name, object: object, queue: .main) { _ in onMainThread { handler() } }
    }

    @discardableResult
    package func observeOnMain<Payload: Sendable>(
        _ name: Notification.Name?, object: Any? = nil, payload: @escaping @Sendable (Notification) -> Payload,
        handler: @escaping @MainActor (Payload) -> Void
    ) -> any NSObjectProtocol {
        addObserver(forName: name, object: object, queue: .main) { note in
            let value = payload(note)
            onMainThread { handler(value) }
        }
    }
}

extension Timer {
    @MainActor
    package static func onMain<Owner: AnyObject & Sendable>(
        every interval: TimeInterval, mode: RunLoop.Mode = .default, owner: Owner,
        _ tick: @escaping @MainActor (Owner) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak owner] timer in
            guard let owner else { return timer.invalidate() }
            onMainThread { tick(owner) }
        }
        RunLoop.main.add(timer, forMode: mode)
        return timer
    }
}
