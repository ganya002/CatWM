import AppKit

@MainActor final class DesktopMenuBarLease {
    let state: DesktopMenuBar.State
    private var panel: OuchPanel?
    private var finished = false

    init(state: DesktopMenuBar.State, panel: OuchPanel?) {
        self.state = state
        self.panel = panel
    }

    func finish() async {
        state.restore()
        let restored = await poll(0.2, every: 1_000_000) { self.state.isRestored }
        if restored { state.clear() }
        restore()
    }

    func restore() {
        guard !finished else { return }
        finished = true
        let batch = WindowServerUpdates.shared.begin()
        defer { batch?.finish() }
        state.restore()
        DesktopMenuBarNative.alpha(state.space, -1)
        panel?.close()
        panel = nil
    }
}
