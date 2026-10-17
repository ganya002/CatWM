import CoreGraphics

enum FocusNavigation {
    struct Item {
        let id: CGWindowID
        let frame: CGRect
        let screen: String?
    }

    static func relation(_ f: CGRect, _ o: CGRect, _ dir: Direction) -> (along: CGFloat, across: CGFloat, overlaps: Bool, edge: CGFloat) {
        let dx = o.midX - f.midX, dy = o.midY - f.midY
        let rows = o.minY < f.maxY && o.maxY > f.minY, cols = o.minX < f.maxX && o.maxX > f.minX
        switch dir {
        case .left: return (-dx, dy, rows, f.minX - o.maxX)
        case .right: return (dx, dy, rows, o.minX - f.maxX)
        case .up: return (-dy, dx, cols, f.minY - o.maxY)
        case .down: return (dy, dx, cols, o.minY - f.maxY)
        }
    }

    static func neighbor(of w: Item, _ dir: Direction, among candidates: [Item], stamps: [CGWindowID: Int]) -> CGWindowID? {
        var scored: [(id: CGWindowID, score: CGFloat, edge: CGFloat)] = []
        for o in candidates where o.id != w.id {
            let (along, across, overlaps, edge) = relation(w.frame, o.frame, dir)
            guard along > 1 else { continue }
            guard overlaps || o.screen != w.screen else { continue }
            scored.append((o.id, along + abs(across) * 2 + (overlaps ? 0 : 100_000), overlaps ? max(0, edge) : .infinity))
        }
        guard let best = scored.min(by: { $0.score < $1.score }) else { return nil }
        guard let nearest = scored.map(\.edge).min(), nearest.isFinite else { return best.id }
        let adjacent = scored.filter { $0.edge <= nearest + 2 }
        let recent = adjacent.max { (stamps[$0.id] ?? 0) < (stamps[$1.id] ?? 0) }
        if let recent, stamps[recent.id] != nil { return recent.id }
        return adjacent.min(by: { $0.score < $1.score })?.id ?? best.id
    }

    static func target(from w: Item, _ dir: Direction, among candidates: [Item], stamps: [CGWindowID: Int]) -> CGWindowID? {
        if let n = neighbor(of: w, dir, among: candidates, stamps: stamps) { return n }
        let here = candidates.filter { $0.id != w.id && $0.screen == w.screen }
        let behind = here.compactMap { o -> (CGWindowID, CGFloat)? in
            let r = relation(w.frame, o.frame, dir)
            return r.overlaps && r.along < -1 ? (o.id, -r.along) : nil
        }
        if let far = behind.map(\.1).max() {
            let ends = behind.filter { $0.1 >= far - 2 }.map(\.0)
            return ends.max { (stamps[$0] ?? 0) < (stamps[$1] ?? 0) }
        }
        let hereIDs = Set(here.map(\.id))
        let stack = candidates.filter { $0.id == w.id || (hereIDs.contains($0.id) && $0.frame.approxEqual(w.frame, tolerance: 2)) }
        guard stack.count > 1, let i = stack.firstIndex(where: { $0.id == w.id }) else { return nil }
        let delta = dir == .left || dir == .up ? -1 : 1
        return stack[((i + delta) % stack.count + stack.count) % stack.count].id
    }
}
