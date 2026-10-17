import CoreGraphics

func fitMinimums(_ frames: [CGRect], mins: [CGSize?], gap: CGFloat) -> [CGRect] {
    guard mins.contains(where: { $0 != nil }) else { return frames }
    guard frames.allSatisfy({ [$0.minX, $0.minY, $0.width, $0.height].allSatisfy { $0.isFinite && abs($0) < 1e9 } }) else { return frames }
    func key(_ v: CGFloat) -> String { "\(v.rounded() + 0)" }
    var out = frames
    for vertical in [true, false] {
        let groups = Dictionary(grouping: out.indices) { i -> String in
            let f = out[i]
            return vertical ? "\(key(f.minX)):\(key(f.width))" : "\(key(f.minY)):\(key(f.height))"
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
