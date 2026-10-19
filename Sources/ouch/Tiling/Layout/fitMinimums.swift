import CoreGraphics

func fitMinimums(_ frames: [CGRect], mins: [CGSize?], gap: CGFloat) -> [CGRect] {
    guard mins.contains(where: { $0 != nil }) else { return frames }
    guard frames.allSatisfy({
        [$0.minX, $0.minY, $0.width, $0.height].allSatisfy { $0.isFinite && abs($0) < 1e9 }
    }) else { return frames }
    func key(_ value: CGFloat) -> String { "\(value.rounded() + 0)" }
    var out = frames
    for vertical in [true, false] {
        let groups = Dictionary(grouping: out.indices) { i -> String in
            let frame = out[i]
            return vertical ? "\(key(frame.minX)):\(key(frame.width))" : "\(key(frame.minY)):\(key(frame.height))"
        }
        for idx in groups.values where idx.count > 1 {
            let sorted = idx.sorted { vertical ? out[$0].minY < out[$1].minY : out[$0].minX < out[$1].minX }
            let starts = sorted.map { vertical ? out[$0].minY : out[$0].minX }
            guard Set(starts.map { $0.rounded() }).count == starts.count else { continue }
            let sizes = sorted.map { vertical ? out[$0].height : out[$0].width }
            let need = sorted.map { i -> CGFloat in vertical ? (mins[i]?.height ?? 0) : (mins[i]?.width ?? 0) }
            guard zip(need, sizes).contains(where: { $0 > $1 + 1 }) else { continue }
            let total = sizes.reduce(0, +)
            guard need.reduce(0, +) <= total else { continue }
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
            for (position, i) in sorted.enumerated() {
                let size = pinned.contains(position) ? need[position] : share
                let frame = out[i]
                out[i] = vertical ? CGRect(x: frame.minX, y: pos, width: frame.width, height: size)
                                  : CGRect(x: pos, y: frame.minY, width: size, height: frame.height)
                pos += size + gap
            }
        }
    }
    return out.map(\.pixelAligned)
}
