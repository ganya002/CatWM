import AppKit

extension WindowManager {
    package func moveFocus(_ direction: Direction) {
        guard let window = focusedWindow() else {
            if let current = context(), let first = current.ids.first.flatMap({ windows[$0] }) { focus(first) }
            return
        }
        let candidates = order.filter { visible.contains($0) && !tabs.isBehind($0) }.compactMap { windows[$0] }
        if let target = resolve(direction, from: window, among: candidates) { focus(target) }
    }

    package func focus(_ target: MotionTarget) {
        switch target {
        case let .window(window): focus(window)
        case let .monitor(screen): focus(on: screen)
        }
    }

    package func focus(on screen: Screen) {
        let screens = backend.screens()
        let topmost = CGWindowInfo.onScreen().first { info in
            guard visible.contains(info.id), let window = windows[info.id] else { return false }
            return self.screen(of: window, in: screens)?.uuid == screen.uuid
        }
        if let id = topmost?.id ?? tiled(on: screen).first, let window = windows[id] {
            focus(window)
        } else {
            parkFocus(on: screen)
        }
    }
}
