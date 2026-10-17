import CoreGraphics

enum Layout: String, CaseIterable {
    case tall, tallRight = "tall-right", wide, middleWide = "middle-wide", fullscreen, column, row, floating, bsp
    case threeColumnLeft = "3column-left", threeColumnMiddle = "3column-middle", threeColumnRight = "3column-right"
    case twoPane = "two-pane", twoPaneRight = "two-pane-right"
    case widescreenTall = "widescreen-tall", widescreenTallRight = "widescreen-tall-right"

    var title: String {
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

    var shortTitle: String {
        switch self {
        case .bsp: "BSP"
        case .widescreenTall: "Wide Tall"
        case .widescreenTallRight: "Wide Tall Right"
        default: title
        }
    }

    func frames(count n: Int, in r: CGRect, ratio: CGFloat, mainCount: Int) -> [CGRect]? {
        guard n > 0 else { return [] }
        let m = max(1, min(mainCount, n))
        switch self {
        case .floating:
            return nil
        case .fullscreen:
            return Array(repeating: r, count: n)
        case .column:
            return columns(r, n)
        case .row:
            return rows(r, n)
        case .tall, .tallRight:
            guard n > m else { return rows(r, n) }
            let (main, rest) = r.divided(atDistance: r.width * ratio, from: self == .tall ? .minXEdge : .maxXEdge)
            return rows(main, m) + rows(rest, n - m)
        case .wide:
            guard n > m else { return columns(r, n) }
            let (main, rest) = r.divided(atDistance: r.height * ratio, from: .minYEdge)
            return columns(main, m) + columns(rest, n - m)
        case .widescreenTall, .widescreenTallRight:
            guard n > m else { return columns(r, n) }
            let (main, rest) = r.divided(atDistance: r.width * ratio, from: self == .widescreenTall ? .minXEdge : .maxXEdge)
            return columns(main, m) + rows(rest, n - m)
        case .twoPane, .twoPaneRight:
            guard n > 1 else { return [r] }
            let (main, rest) = r.divided(atDistance: r.width * ratio, from: self == .twoPane ? .minXEdge : .maxXEdge)
            return [main] + Array(repeating: rest, count: n - 1)
        case .middleWide, .threeColumnMiddle:
            if n <= m { return columns(r, n) }
            if n == m + 1 { return Layout.tall.frames(count: n, in: r, ratio: ratio, mainCount: m) }
            let mainW = r.width * ratio, sideW = (r.width - mainW) / 2
            let left = CGRect(x: r.minX, y: r.minY, width: sideW, height: r.height)
            let main = CGRect(x: left.maxX, y: r.minY, width: mainW, height: r.height)
            let right = CGRect(x: main.maxX, y: r.minY, width: r.maxX - main.maxX, height: r.height)
            let rest = n - m, l = (rest + 1) / 2
            return rows(main, m) + rows(left, l) + rows(right, rest - l)
        case .threeColumnLeft, .threeColumnRight:
            if n <= m { return columns(r, n) }
            let left = self == .threeColumnLeft
            if n == m + 1 { return (left ? Layout.tall : .tallRight).frames(count: n, in: r, ratio: ratio, mainCount: m) }
            let (main, rest) = r.divided(atDistance: r.width * ratio, from: left ? .minXEdge : .maxXEdge)
            let (near, far) = rest.divided(atDistance: rest.width / 2, from: left ? .minXEdge : .maxXEdge)
            let count = n - m, a = (count + 1) / 2
            return rows(main, m) + rows(near, a) + rows(far, count - a)
        case .bsp:
            var out: [CGRect] = [], rest = r
            for i in 0..<n {
                if i == n - 1 { out.append(rest); break }
                let vertical = rest.width >= rest.height
                let amount = (vertical ? rest.width : rest.height) * (i == 0 ? ratio : 0.5)
                let (a, b) = rest.divided(atDistance: amount, from: vertical ? .minXEdge : .minYEdge)
                out.append(a); rest = b
            }
            return out
        }
    }

    var ratioAxis: (horizontal: Bool, fromStart: Bool)? {
        switch self {
        case .tall, .widescreenTall, .twoPane, .threeColumnLeft, .bsp: (true, true)
        case .tallRight, .widescreenTallRight, .twoPaneRight, .threeColumnRight: (true, false)
        case .wide: (false, true)
        default: nil
        }
    }
}
