import AppKit
import CoreGraphics

package enum MotionResolver {
    package struct Item {
        package let id: CGWindowID
        package let frame: CGRect
        package let screen: String?
    }

    package struct Display {
        package let id: String
        package let frame: CGRect
    }

    package enum Hit: Equatable {
        case window(CGWindowID)
        case monitor(String)
    }

    package struct Relation {
        package let along: CGFloat
        package let across: CGFloat
        package let overlaps: Bool
        package let edge: CGFloat
    }

    private struct Scored {
        package let id: CGWindowID
        package let score: CGFloat
        package let edge: CGFloat
    }

    package static func resolve(
        from item: Item, _ dir: Direction, among candidates: [Item], displays: [Display], stamps: [CGWindowID: Int]
    ) -> Hit? {
        let local = candidates.filter { $0.screen == item.screen }
        if let next = neighbor(of: item, dir, among: local, stamps: stamps) { return .window(next) }
        if let here = displays.first(where: { $0.id == item.screen }),
           let next = display(from: here, dir, among: displays) {
            let there = candidates.filter { $0.screen == next }
            if let window = neighbor(of: item, dir, among: there, stamps: stamps) { return .window(window) }
            return .monitor(next)
        }
        if let next = neighbor(of: item, dir, among: candidates, stamps: stamps) { return .window(next) }
        return wrap(from: item, dir, among: candidates, stamps: stamps).map(Hit.window)
    }

    package static func relation(_ from: CGRect, _ other: CGRect, _ dir: Direction) -> Relation {
        let dx = other.midX - from.midX, dy = other.midY - from.midY
        let rows = other.minY < from.maxY && other.maxY > from.minY
        let cols = other.minX < from.maxX && other.maxX > from.minX
        switch dir {
        case .left: return Relation(along: -dx, across: dy, overlaps: rows, edge: from.minX - other.maxX)
        case .right: return Relation(along: dx, across: dy, overlaps: rows, edge: other.minX - from.maxX)
        case .upward: return Relation(along: -dy, across: dx, overlaps: cols, edge: from.minY - other.maxY)
        case .down: return Relation(along: dy, across: dx, overlaps: cols, edge: other.minY - from.maxY)
        }
    }

    package static func neighbor(
        of item: Item, _ dir: Direction, among candidates: [Item], stamps: [CGWindowID: Int]
    ) -> CGWindowID? {
        var scored: [Scored] = []
        for other in candidates where other.id != item.id {
            let geometry = relation(item.frame, other.frame, dir)
            guard geometry.along > 1 else { continue }
            guard geometry.overlaps || other.screen != item.screen else { continue }
            scored.append(Scored(id: other.id,
                                 score: geometry.along + abs(geometry.across) * 2 + (geometry.overlaps ? 0 : 100_000),
                                 edge: geometry.overlaps ? max(0, geometry.edge) : .infinity))
        }
        guard let best = scored.min(by: { $0.score < $1.score }) else { return nil }
        guard let nearest = scored.map(\.edge).min(), nearest.isFinite else { return best.id }
        let adjacent = scored.filter { $0.edge <= nearest + 2 }
        let recent = adjacent.max { (stamps[$0.id] ?? 0) < (stamps[$1.id] ?? 0) }
        if let recent, stamps[recent.id] != nil { return recent.id }
        return adjacent.min(by: { $0.score < $1.score })?.id ?? best.id
    }

    package static func display(from here: Display, _ dir: Direction, among displays: [Display]) -> String? {
        let beyond = displays.compactMap { other -> (String, CGFloat)? in
            let geometry = relation(here.frame, other.frame, dir)
            return other.id != here.id && geometry.overlaps && geometry.edge > -2 ? (other.id, geometry.edge) : nil
        }
        return beyond.min { $0.1 < $1.1 }?.0
    }

    package static func wrap(
        from item: Item, _ dir: Direction, among candidates: [Item], stamps: [CGWindowID: Int]
    ) -> CGWindowID? {
        let here = candidates.filter { $0.id != item.id && $0.screen == item.screen }
        let behind = here.compactMap { other -> (CGWindowID, CGFloat)? in
            let geometry = relation(item.frame, other.frame, dir)
            return geometry.overlaps && geometry.along < -1 ? (other.id, -geometry.along) : nil
        }
        if let far = behind.map(\.1).max() {
            let ends = behind.filter { $0.1 >= far - 2 }.map(\.0)
            return ends.max { (stamps[$0] ?? 0) < (stamps[$1] ?? 0) }
        }
        let hereIDs = Set(here.map(\.id))
        let stack = candidates.filter {
            $0.id == item.id || (hereIDs.contains($0.id) && $0.frame.approxEqual(item.frame, tolerance: 2))
        }
        return cycle(item.id, in: stack.map(\.id), dir)
    }

    package static func cycle(_ id: CGWindowID, in ids: [CGWindowID], _ dir: Direction) -> CGWindowID? {
        guard ids.count > 1, let i = ids.firstIndex(of: id) else { return nil }
        let delta = dir == .left || dir == .upward ? -1 : 1
        return ids[((i + delta) % ids.count + ids.count) % ids.count]
    }
}

package enum MotionTarget {
    case window(Window)
    case monitor(Screen)
}

extension WindowManager {
    package func resolve(_ direction: Direction, from window: Window, among candidates: [Window]) -> MotionTarget? {
        let screens = backend.screens()
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

    package func navItem(_ window: Window, in screens: [Screen]) -> MotionResolver.Item {
        .init(id: window.id, frame: navFrame(window), screen: screen(of: window, in: screens)?.uuid)
    }
}

package enum Direction: String, CaseIterable {
    case left = "l", right = "r", upward = "u", down = "d"

    package var title: String { symbolName.capitalized }
    package var symbolName: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .upward: "up"
        case .down: "down"
        }
    }

    package static let hintArrows = Dictionary(uniqueKeysWithValues: allCases.flatMap { direction in
        let arrow: String
        switch direction {
        case .left: arrow = "←"
        case .right: arrow = "→"
        case .upward: arrow = "↑"
        case .down: arrow = "↓"
        }
        return [(direction.rawValue, arrow), (direction.symbolName, arrow)]
    })
    package init?(_ text: String) {
        switch text.lowercased() {
        case "l", "left": self = .left
        case "r", "right": self = .right
        case "u", "up", "t", "top": self = .upward
        case "d", "down", "b", "bottom": self = .down
        default: return nil
        }
    }
}
