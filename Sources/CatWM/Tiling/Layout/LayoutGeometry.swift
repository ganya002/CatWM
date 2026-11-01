import AppKit
import CoreGraphics

func fitMinimums(_ frames: [CGRect], mins: [CGSize?], gap: CGFloat) -> [CGRect] {
    guard mins.contains(where: { $0 != nil }) else { return frames }
    guard frames.allSatisfy({
        [$0.minX, $0.minY, $0.width, $0.height].allSatisfy { $0.isFinite && abs($0) < 1e9 }
    }) else { return frames }
    func key(_ value: CGFloat) -> String { "\(value.rounded() + 0)" }
    var out = frames
    for vertical in [true, false] {
        let units = Array(Dictionary(grouping: out.indices) {
            vertical ? "\(key(out[$0].minY)):\(key(out[$0].height))" : "\(key(out[$0].minX)):\(key(out[$0].width))"
        }.values)
        let groups = Dictionary(grouping: units) { unit -> String in
            let span = unit.map { out[$0] }.reduce(CGRect.null) { $0.union($1) }
            return vertical ? "\(key(span.minX)):\(key(span.width))" : "\(key(span.minY)):\(key(span.height))"
        }
        for group in groups.values where group.count > 1 {
            fit(group, in: &out, mins: mins, gap: gap, vertical: vertical)
        }
    }
    return out.map(\.pixelAligned)
}

private func fit(_ group: [[Int]], in out: inout [CGRect], mins: [CGSize?], gap: CGFloat, vertical: Bool) {
    let sorted = group.sorted { vertical ? out[$0[0]].minY < out[$1[0]].minY : out[$0[0]].minX < out[$1[0]].minX }
    let starts = sorted.map { vertical ? out[$0[0]].minY : out[$0[0]].minX }
    let sizes = sorted.map { vertical ? out[$0[0]].height : out[$0[0]].width }
    guard zip(starts, zip(starts.dropFirst(), sizes)).allSatisfy({ $1.0 >= $0 + $1.1 - 1 }) else { return }
    let need = sorted.map { unit in
        unit.map { vertical ? (mins[$0]?.height ?? 0) : (mins[$0]?.width ?? 0) }.max() ?? 0
    }
    guard zip(need, sizes).contains(where: { $0 > $1 + 1 }) else { return }
    let total = sizes.reduce(0, +)
    guard need.reduce(0, +) <= total else { return }
    let growth = zip(need, sizes).map { max(0, $0 - $1) }.reduce(0, +)
    let spare = zip(sizes, need).map { max(0, $0 - $1) }
    let available = spare.reduce(0, +)
    var pos = starts[0]
    for (position, unit) in sorted.enumerated() {
        let size = need[position] > sizes[position] ? need[position]
            : sizes[position] - growth * spare[position] / available
        for i in unit {
            let frame = out[i]
            out[i] = vertical ? CGRect(x: frame.minX, y: pos, width: frame.width, height: size)
                              : CGRect(x: pos, y: frame.minY, width: size, height: frame.height)
        }
        pos += size + gap
    }
}

func clampToMinimum(_ slot: CGRect, min: CGSize?, bounds: CGRect) -> CGRect {
    guard let min, slot.minX.isFinite, slot.minY.isFinite else { return slot }
    let width = min.width > slot.width + 1 ? min.width : slot.width
    let height = min.height > slot.height + 1 ? min.height : slot.height
    guard width != slot.width || height != slot.height else { return slot }
    let x = max(bounds.minX, Swift.min(slot.minX, bounds.maxX - width))
    let y = max(bounds.minY, Swift.min(slot.minY, bounds.maxY - height))
    return CGRect(x: x, y: y, width: width, height: height).pixelAligned
}

func columns(_ rect: CGRect, _ count: Int) -> [CGRect] {
    guard count > 0 else { return [] }
    let width = rect.width / CGFloat(count)
    return (0..<count).map {
        CGRect(x: rect.minX + CGFloat($0) * width, y: rect.minY, width: width, height: rect.height)
    }
}

func rows(_ rect: CGRect, _ count: Int) -> [CGRect] {
    guard count > 0 else { return [] }
    let height = rect.height / CGFloat(count)
    return (0..<count).map {
        CGRect(x: rect.minX, y: rect.minY + CGFloat($0) * height, width: rect.width, height: height)
    }
}

extension Layout {
    var hasMainPane: Bool {
        switch self {
        case .fullscreen, .column, .row, .floating: false
        default: true
        }
    }
}
