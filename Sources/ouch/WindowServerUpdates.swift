import AppKit

/// Keeps the last composed frame visible during a native-Space import. WindowServer
/// membership and AX writes still proceed; their intermediate states are presented together.
/// Each batch has an independent watchdog so an unresponsive app cannot hold the display.
final class WindowServerUpdates {
    final class Lease {
        private let lock = NSLock()
        private var release: (() -> Void)?
        init(_ release: @escaping () -> Void) { self.release = release }
        func finish() {
            let action = lock.withLock { let action = release; release = nil; return action }
            action?()
        }
        deinit { finish() }
    }

    private typealias Connection = @convention(c) () -> Int32
    private typealias Update = @convention(c) (Int32) -> Int32
    static let shared: WindowServerUpdates = {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func lookup<T>(_ name: String, as: T.Type) -> T? {
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

    private let lock = NSLock()
    private let disable: () -> Bool
    private let enable: () -> Void
    let maximumHold: Double
    private var generation = 0
    private var leases = 0

    // Injectable operations let the lifecycle probe run without touching WindowServer.
    // An import measured 45–60 ms for the Space move alone, before any AX write. The hold must
    // cover the move and the relayout around it, or the screen shows the import half done.
    init(maximumHold: Double = 0.3, disable: @escaping () -> Bool, enable: @escaping () -> Void) {
        self.maximumHold = maximumHold; self.disable = disable; self.enable = enable
    }

    func begin() -> Lease? {
        lock.lock()
        if leases == 0 {
            guard disable() else { lock.unlock(); return nil }
            generation += 1
            let batch = generation
            // Off the main queue: even a hung AX call cannot prevent the release.
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + maximumHold) { [self] in
                finish(batch, force: true)
            }
        }
        leases += 1
        let batch = generation
        lock.unlock()
        return Lease { [self] in finish(batch, force: false) }
    }

    private func finish(_ batch: Int, force: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard generation == batch, leases > 0 else { return }
        leases = force ? 0 : leases - 1
        if leases == 0 { enable() }
    }
}
