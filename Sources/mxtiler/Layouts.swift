import CoreGraphics

/// Amethyst's layouts. Frames are computed in top-left-origin coordinates; `nil` means "don't touch".
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
        case .threeColumnLeft: "3Column Left"
        case .threeColumnMiddle: "3Column Middle"
        case .threeColumnRight: "3Column Right"
        case .twoPane: "Two Pane"
        case .twoPaneRight: "Two Pane Right"
        case .widescreenTall: "Widescreen Tall"
        case .widescreenTallRight: "Widescreen Tall Right"
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

    /// Which axis the main/secondary boundary lies on, used for mouse-resizing. `fromStart` is
    /// true when the main pane sits at the left/top.
    var ratioAxis: (horizontal: Bool, fromStart: Bool)? {
        switch self {
        case .tall, .widescreenTall, .twoPane, .threeColumnLeft, .bsp: (true, true)
        case .tallRight, .widescreenTallRight, .twoPaneRight, .threeColumnRight: (true, false)
        case .wide: (false, true)
        default: nil
        }
    }
}

private func columns(_ r: CGRect, _ n: Int) -> [CGRect] {
    guard n > 0 else { return [] }
    let w = r.width / CGFloat(n)
    return (0..<n).map { CGRect(x: r.minX + CGFloat($0) * w, y: r.minY, width: w, height: r.height) }
}

private func rows(_ r: CGRect, _ n: Int) -> [CGRect] {
    guard n > 0 else { return [] }
    let h = r.height / CGFloat(n)
    return (0..<n).map { CGRect(x: r.minX, y: r.minY + CGFloat($0) * h, width: r.width, height: h) }
}

/// Windows with a minimum size larger than their slot would overlap their neighbours. Within each
/// stack (windows sharing a column or a row), give those windows their minimum and split the rest
/// of the stack evenly between the others. Stacks that can't fit everyone are left alone.
func fitMinimums(_ frames: [CGRect], mins: [CGSize?], gap: CGFloat) -> [CGRect] {
    guard mins.contains(where: { $0 != nil }) else { return frames }
    var out = frames
    for vertical in [true, false] {
        let groups = Dictionary(grouping: out.indices) { i -> String in
            let f = out[i]
            return vertical ? "\(Int(f.minX.rounded())):\(Int(f.width.rounded()))" : "\(Int(f.minY.rounded())):\(Int(f.height.rounded()))"
        }
        for idx in groups.values where idx.count > 1 {
            let sorted = idx.sorted { vertical ? out[$0].minY < out[$1].minY : out[$0].minX < out[$1].minX }
            let starts = sorted.map { vertical ? out[$0].minY : out[$0].minX }
            guard Set(starts.map { Int($0.rounded()) }).count == starts.count else { continue } // stacked on top of each other
            let sizes = sorted.map { vertical ? out[$0].height : out[$0].width }
            let need = sorted.map { i -> CGFloat in vertical ? (mins[i]?.height ?? 0) : (mins[i]?.width ?? 0) }
            guard zip(need, sizes).contains(where: { $0 > $1 + 1 }) else { continue }
            let total = sizes.reduce(0, +)
            guard need.reduce(0, +) <= total else { continue }
            // Water-filling: anyone whose minimum beats the even share is pinned to it.
            var pinned = Set<Int>()
            var share: CGFloat = 0
            while true {
                let free = sorted.indices.filter { !pinned.contains($0) }
                let left = total - pinned.map { need[$0] }.reduce(0, +)
                share = free.isEmpty ? 0 : left / CGFloat(free.count)
                let more = free.filter { need[$0] > share }
                if more.isEmpty { break }
                pinned.formUnion(more)
            }
            var pos = starts[0]
            for (k, i) in sorted.enumerated() {
                let size = pinned.contains(k) ? need[k] : share
                let f = out[i]
                out[i] = vertical ? CGRect(x: f.minX, y: pos, width: f.width, height: size)
                                  : CGRect(x: pos, y: f.minY, width: size, height: f.height)
                pos += size + gap
            }
        }
    }
    return out.map(\.pixelAligned)
}
