import AppKit

extension WindowManager {
    @discardableResult
    package func changeDwindle(of target: Window? = nil,
                               _ change: (inout DwindleTree, _ index: Int, _ area: CGRect) -> Void) -> Bool {
        guard let window = target ?? focusedWindow(), let screen = screen(of: window) else { return false }
        let screenState = state(for: screen)
        let ids = tiled(on: screen)
        guard screenState.layout == .dwindle, let index = ids.firstIndex(of: window.id) else { return false }
        let gap = windowGap(count: ids.count, on: screen)
        screenState.dwindle.sync(ids)
        change(&screenState.dwindle, index, usableRect(screen).insetBy(dx: -gap / 2, dy: -gap / 2))
        refresh()
        return true
    }

    package func resizeWindow(_ window: Window, by delta: CGSize) {
        if changeDwindle(of: window, { $0.resize(at: $1, by: delta, in: $2) }) { return }
        let frame = animator.destination(window.id) ?? window.cachedFrame
        guard !frame.isNull else { return }
        resizeWindow(window, to: CGSize(width: max(1, frame.width + delta.width),
                                        height: max(1, frame.height + delta.height)))
    }
}
