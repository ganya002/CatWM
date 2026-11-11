import AppKit
import os

package final class WindowServerUpdates: Sendable {
    package final class Lease: Sendable {
        private let release: OSAllocatedUnfairLock<(@Sendable () -> Void)?>
        package init(_ release: @escaping @Sendable () -> Void) {
            self.release = OSAllocatedUnfairLock(initialState: release)
        }
        package func finish() {
            let action = release.withLock { action in let taken = action; action = nil; return taken }
            action?()
        }
        deinit { finish() }
    }

    private typealias Connection = @convention(c) () -> Int32
    private typealias Update = @convention(c) (Int32) -> Int32
    package static let shared: WindowServerUpdates = {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func lookup<T>(_ name: String, as _: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        let connection = lookup("SLSMainConnectionID", as: Connection.self)
        let disable = lookup("SLSDisableUpdate", as: Update.self)
        let enable = lookup("SLSReenableUpdate", as: Update.self)
        let cid = connection?() ?? 0
        return WindowServerUpdates(disable: {
            guard cid != 0, enable != nil, let disable else { return false }
            return disable(cid) == 0
        }, enable: { _ = enable?(cid) })
    }()

    private struct State {
        var generation = 0
        var leases = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let disable: @Sendable () -> Bool
    private let enable: @Sendable () -> Void
    package let maximumHold: Double

    package init(maximumHold: Double = 0.3, disable: @escaping @Sendable () -> Bool,
                 enable: @escaping @Sendable () -> Void) {
        self.maximumHold = maximumHold; self.disable = disable; self.enable = enable
    }

    package func begin() -> Lease? {
        let batch: Int? = state.withLock { state in
            if state.leases == 0 {
                guard disable() else { return nil }
                state.generation += 1
                let batch = state.generation
                DispatchQueue.global(qos: .userInteractive).asyncAfter( // style-ok: limit for a lost lease
                    deadline: .now() + maximumHold
                ) { [self] in
                    finish(batch, force: true)
                }
            }
            state.leases += 1
            return state.generation
        }
        guard let batch else { return nil }
        return Lease { [self] in finish(batch, force: false) }
    }

    private func finish(_ batch: Int, force: Bool) {
        state.withLock { state in
            guard state.generation == batch, state.leases > 0 else { return }
            state.leases = force ? 0 : state.leases - 1
            if state.leases == 0 { enable() }
        }
    }
}
