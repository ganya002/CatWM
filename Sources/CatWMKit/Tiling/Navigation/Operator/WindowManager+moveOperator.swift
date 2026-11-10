import AppKit

extension WindowManager {
    package func moveWindow(_ direction: Direction) {
        guard let window = focusedWindow(), !window.isFloating else { return }
        let candidates = order.filter { visible.contains($0) && !tabs.isBehind($0) }.compactMap { windows[$0] }
            .filter { !$0.isFloating }
        if let target = resolve(direction, from: window, among: candidates) { move(window, to: target) }
    }

    package func move(_ window: Window, to target: MotionTarget) {
        switch target {
        case let .window(other):
            if let from = screen(of: window), let into = screen(of: other), from.uuid != into.uuid {
                assignTabs(of: window.id, to: shown[into.uuid])
            } else {
                swapOrder(window.id, other.id)
            }
        case let .monitor(screen):
            assignTabs(of: window.id, to: shown[screen.uuid])
        }
        refresh()
        focus(window)
        if case let .window(other) = target, other.pid != window.pid {
            focusRequests.focusEcho = FocusEcho(id: window.id, other: other.pid)
        }
    }
}
