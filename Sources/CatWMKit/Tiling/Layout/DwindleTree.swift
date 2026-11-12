import CoreGraphics

package struct DwindleSplit: Equatable {
    package var sideBySide: Bool?
    package var ratio: CGFloat = 0.5
    package var swapped = false
    package var first: DwindleNode
    package var second: DwindleNode
}

package indirect enum DwindleNode: Equatable {
    case leaf
    case split(DwindleSplit)

    var leafCount: Int {
        switch self {
        case .leaf: 1
        case .split(let split): split.first.leafCount + split.second.leafCount
        }
    }
}

package struct DwindleTree: Equatable {
    private struct Step {
        let sideBySide: Bool
        let inFirst: Bool
        let rect: CGRect
    }

    package private(set) var root: DwindleNode?
    package private(set) var ids: [CGWindowID] = []

    package init() {}

    package mutating func sync(_ new: [CGWindowID]) {
        guard new != ids else { return }
        let kept = Set(new), old = Set(ids)
        for index in ids.indices.reversed() where !kept.contains(ids[index]) {
            root = root.flatMap { Self.removing(index, from: $0) }
        }
        for (index, id) in new.enumerated() where !old.contains(id) {
            guard let current = root else { root = .leaf; continue }
            root = Self.splitting(max(0, index - 1), in: current)
        }
        ids = new
    }

    package func frames(in rect: CGRect) -> [CGRect] {
        root.map { Self.frames(of: $0, in: rect) } ?? []
    }

    package mutating func toggleSplit(at index: Int, in rect: CGRect) {
        let steps = steps(to: index, in: rect)
        guard let parent = steps.last else { return }
        modify(depth: steps.count - 1, along: steps) { $0.sideBySide = !parent.sideBySide }
    }

    package mutating func swapSplit(at index: Int, in rect: CGRect) {
        let steps = steps(to: index, in: rect)
        guard !steps.isEmpty else { return }
        modify(depth: steps.count - 1, along: steps) { $0.swapped.toggle() }
    }

    @discardableResult
    package mutating func setRatio(at index: Int, in rect: CGRect, _ change: (CGFloat) -> CGFloat) -> CGFloat? {
        let steps = steps(to: index, in: rect)
        guard !steps.isEmpty else { return nil }
        var ratio: CGFloat?
        modify(depth: steps.count - 1, along: steps) {
            $0.ratio = min(0.9, max(0.1, change($0.ratio)))
            ratio = $0.ratio
        }
        return ratio
    }

    package mutating func resize(at index: Int, by delta: CGSize, in rect: CGRect) {
        let steps = steps(to: index, in: rect)
        for (sideBySide, amount) in [(true, delta.width), (false, delta.height)] where amount != 0 {
            guard let depth = steps.lastIndex(where: { $0.sideBySide == sideBySide }) else { continue }
            let step = steps[depth]
            let length = sideBySide ? step.rect.width : step.rect.height
            guard length > 0 else { continue }
            let change = (step.inFirst ? 1 : -1) * amount / length
            modify(depth: depth, along: steps) { $0.ratio = min(0.9, max(0.1, $0.ratio + change)) }
        }
    }

    private func steps(to index: Int, in rect: CGRect) -> [Step] {
        var steps: [Step] = [], node = root, rect = rect, index = index
        while case .split(let split)? = node {
            let sideBySide = split.sideBySide ?? (rect.width >= rect.height)
            let (first, second) = Self.divide(rect, split, sideBySide: sideBySide)
            let count = split.first.leafCount
            let inFirst = index < count
            steps.append(Step(sideBySide: sideBySide, inFirst: inFirst, rect: rect))
            node = inFirst ? split.first : split.second
            rect = inFirst ? first : second
            if !inFirst { index -= count }
        }
        return steps
    }

    private mutating func modify(depth: Int, along steps: [Step], _ change: (inout DwindleSplit) -> Void) {
        root = root.map { Self.modify($0, steps: steps[...], depth: depth, change) }
    }

    private static func modify(_ node: DwindleNode, steps: ArraySlice<Step>, depth: Int,
                               _ change: (inout DwindleSplit) -> Void) -> DwindleNode {
        guard case .split(var split) = node, let step = steps.first else { return node }
        if depth == 0 {
            change(&split)
        } else if step.inFirst {
            split.first = modify(split.first, steps: steps.dropFirst(), depth: depth - 1, change)
        } else {
            split.second = modify(split.second, steps: steps.dropFirst(), depth: depth - 1, change)
        }
        return .split(split)
    }

    private static func divide(_ rect: CGRect, _ split: DwindleSplit, sideBySide: Bool) -> (CGRect, CGRect) {
        let length = (sideBySide ? rect.width : rect.height) * split.ratio
        let edge: CGRectEdge = sideBySide ? (split.swapped ? .maxXEdge : .minXEdge)
            : (split.swapped ? .maxYEdge : .minYEdge)
        let (slice, remainder) = rect.divided(atDistance: length, from: edge)
        return (slice, remainder)
    }

    private static func frames(of node: DwindleNode, in rect: CGRect) -> [CGRect] {
        guard case .split(let split) = node else { return [rect] }
        let (first, second) = divide(rect, split, sideBySide: split.sideBySide ?? (rect.width >= rect.height))
        return frames(of: split.first, in: first) + frames(of: split.second, in: second)
    }

    private static func removing(_ index: Int, from node: DwindleNode) -> DwindleNode? {
        guard case .split(var split) = node else { return index == 0 ? nil : node }
        let count = split.first.leafCount
        if index < count {
            guard let first = removing(index, from: split.first) else { return split.second }
            split.first = first
        } else {
            guard let second = removing(index - count, from: split.second) else { return split.first }
            split.second = second
        }
        return .split(split)
    }

    private static func splitting(_ index: Int, in node: DwindleNode) -> DwindleNode {
        guard case .split(var split) = node else {
            return .split(DwindleSplit(sideBySide: nil, first: .leaf, second: .leaf))
        }
        let count = split.first.leafCount
        if index < count {
            split.first = splitting(index, in: split.first)
        } else {
            split.second = splitting(index - count, in: split.second)
        }
        return .split(split)
    }
}
