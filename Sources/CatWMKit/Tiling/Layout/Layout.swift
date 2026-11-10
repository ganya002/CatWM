import CoreGraphics

package enum Layout: String, CaseIterable {
    case tall, tallRight = "tall-right", wide, middleWide = "middle-wide", fullscreen, column, row, floating, bsp
    case threeColumnLeft = "3column-left", threeColumnMiddle = "3column-middle", threeColumnRight = "3column-right"
    case twoPane = "two-pane", twoPaneRight = "two-pane-right"
    case widescreenTall = "widescreen-tall", widescreenTallRight = "widescreen-tall-right"

    package var title: String {
        switch self {
        case .tall: "Tall"
        case .tallRight: "Tall Right"
        case .wide: "Wide"
        case .middleWide: "Middle Wide"
        case .fullscreen: "Fullscreen"
        case .column: "Column"
        case .row: "Row"
        case .floating: "Floating"
        case .bsp: "Binary Space Partitioning"
        case .threeColumnLeft: "3-Column Left"
        case .threeColumnMiddle: "3-Column Middle"
        case .threeColumnRight: "3-Column Right"
        case .twoPane: "Two Pane"
        case .twoPaneRight: "Two Pane Right"
        case .widescreenTall: "Widescreen Tall"
        case .widescreenTallRight: "Widescreen Tall Right"
        }
    }

    package var shortTitle: String {
        switch self {
        case .bsp: "BSP"
        case .widescreenTall: "Wide Tall"
        case .widescreenTallRight: "Wide Tall Right"
        default: title
        }
    }

    package func frames(count: Int, in rect: CGRect, ratio: CGFloat, mainCount: Int) -> [CGRect]? {
        guard count > 0 else { return [] }
        let mains = max(1, min(mainCount, count))
        switch self {
        case .floating:
            return nil
        case .fullscreen:
            return Array(repeating: rect, count: count)
        case .column:
            return columns(rect, count)
        case .row:
            return rows(rect, count)
        case .tall, .tallRight:
            guard count > mains else { return rows(rect, count) }
            let (main, rest) = rect.divided(atDistance: rect.width * ratio, from: self == .tall ? .minXEdge : .maxXEdge)
            return rows(main, mains) + rows(rest, count - mains)
        case .wide:
            guard count > mains else { return columns(rect, count) }
            let (main, rest) = rect.divided(atDistance: rect.height * ratio, from: .minYEdge)
            return columns(main, mains) + columns(rest, count - mains)
        case .widescreenTall, .widescreenTallRight:
            guard count > mains else { return columns(rect, count) }
            let (main, rest) = rect.divided(atDistance: rect.width * ratio,
                                            from: self == .widescreenTall ? .minXEdge : .maxXEdge)
            return columns(main, mains) + rows(rest, count - mains)
        case .twoPane, .twoPaneRight:
            guard count > 1 else { return [rect] }
            let (main, rest) = rect.divided(atDistance: rect.width * ratio,
                                            from: self == .twoPane ? .minXEdge : .maxXEdge)
            return [main] + Array(repeating: rest, count: count - 1)
        case .middleWide, .threeColumnMiddle:
            return middleFrames(count: count, in: rect, ratio: ratio, mains: mains)
        case .threeColumnLeft, .threeColumnRight:
            return sideFrames(count: count, in: rect, ratio: ratio, mains: mains)
        case .bsp:
            return Self.bspFrames(count: count, in: rect, ratio: ratio)
        }
    }

    private func middleFrames(count: Int, in rect: CGRect, ratio: CGFloat, mains: Int) -> [CGRect]? {
        if count <= mains { return columns(rect, count) }
        if count == mains + 1 { return Layout.tall.frames(count: count, in: rect, ratio: ratio, mainCount: mains) }
        let mainW = rect.width * ratio, sideW = (rect.width - mainW) / 2
        let left = CGRect(x: rect.minX, y: rect.minY, width: sideW, height: rect.height)
        let main = CGRect(x: left.maxX, y: rect.minY, width: mainW, height: rect.height)
        let right = CGRect(x: main.maxX, y: rect.minY, width: rect.maxX - main.maxX, height: rect.height)
        let rest = count - mains, leftCount = (rest + 1) / 2
        return rows(main, mains) + rows(left, leftCount) + rows(right, rest - leftCount)
    }

    private func sideFrames(count: Int, in rect: CGRect, ratio: CGFloat, mains: Int) -> [CGRect]? {
        if count <= mains { return columns(rect, count) }
        let left = self == .threeColumnLeft
        if count == mains + 1 {
            return (left ? Layout.tall : .tallRight).frames(count: count, in: rect, ratio: ratio, mainCount: mains)
        }
        let (main, rest) = rect.divided(atDistance: rect.width * ratio, from: left ? .minXEdge : .maxXEdge)
        let (near, far) = rest.divided(atDistance: rest.width / 2, from: left ? .minXEdge : .maxXEdge)
        let others = count - mains, nearCount = (others + 1) / 2
        return rows(main, mains) + rows(near, nearCount) + rows(far, others - nearCount)
    }

    private static func bspFrames(count: Int, in rect: CGRect, ratio: CGFloat) -> [CGRect] {
        var out: [CGRect] = [], rest = rect
        for i in 0..<count {
            if i == count - 1 { out.append(rest); break }
            let vertical = rest.width >= rest.height
            let amount = (vertical ? rest.width : rest.height) * (i == 0 ? ratio : 0.5)
            let (slice, remainder) = rest.divided(atDistance: amount, from: vertical ? .minXEdge : .minYEdge)
            out.append(slice)
            rest = remainder
        }
        return out
    }

    package var mirrored: Layout? {
        switch self {
        case .tall: .tallRight
        case .tallRight: .tall
        case .twoPane: .twoPaneRight
        case .twoPaneRight: .twoPane
        case .widescreenTall: .widescreenTallRight
        case .widescreenTallRight: .widescreenTall
        case .threeColumnLeft: .threeColumnRight
        case .threeColumnRight: .threeColumnLeft
        default: nil
        }
    }

    package var ratioAxis: (horizontal: Bool, fromStart: Bool)? {
        switch self {
        case .tall, .widescreenTall, .twoPane, .threeColumnLeft, .bsp: (true, true)
        case .tallRight, .widescreenTallRight, .twoPaneRight, .threeColumnRight: (true, false)
        case .wide: (false, true)
        default: nil
        }
    }
}
