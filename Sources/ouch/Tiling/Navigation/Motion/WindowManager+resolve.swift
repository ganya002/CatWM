import AppKit

enum MotionTarget {
    case window(Window)
    case monitor(Screen)
}

extension WindowManager {
    func resolve(_ direction: Direction, from window: Window, among candidates: [Window]) -> MotionTarget? {
        let screens = Screen.all()
        if let home = screen(of: window, in: screens), state(for: home).zoomed == window.id {
            return MotionResolver.cycle(window.id, in: tiled(on: home), direction)
                .flatMap { windows[$0] }.map(MotionTarget.window)
        }
        let hit = MotionResolver.resolve(from: navItem(window, in: screens), direction,
                                         among: candidates.map { navItem($0, in: screens) },
                                         displays: screens.map { .init(id: $0.uuid, frame: $0.frame) },
                                         stamps: focusStamps)
        switch hit {
        case let .window(id): return windows[id].map(MotionTarget.window)
        case let .monitor(uuid): return screens.first { $0.uuid == uuid }.map(MotionTarget.monitor)
        case nil: return nil
        }
    }

    func navItem(_ window: Window, in screens: [Screen]) -> MotionResolver.Item {
        .init(id: window.id, frame: navFrame(window), screen: screen(of: window, in: screens)?.uuid)
    }
}
