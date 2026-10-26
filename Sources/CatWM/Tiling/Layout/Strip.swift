import CoreGraphics

struct Strip: Equatable {
    struct Column: Equatable {
        var ids: [CGWindowID]
        var width: CGFloat
        var heights: [CGFloat]

        init(_ ids: [CGWindowID], width: CGFloat) {
            self.ids = ids
            self.width = width
            heights = ids.map { _ in 1 }
        }
    }

    enum Scroll: String, CaseIterable {
        case minimum, center
    }

    static let widthRange: ClosedRange<CGFloat> = 0.1...1

    var columns: [Column] = []
    var offset: CGFloat = 0

    var ids: [CGWindowID] { columns.flatMap(\.ids) }

    func column(of id: CGWindowID) -> Int? { columns.firstIndex { $0.ids.contains(id) } }

    mutating func sync(_ tiled: [CGWindowID], focus: CGWindowID?, width: CGFloat) {
        let keep = Set(tiled)
        for index in columns.indices {
            let kept = columns[index].ids.indices.filter { keep.contains(columns[index].ids[$0]) }
            columns[index].heights = kept.map { columns[index].heights[$0] }
            columns[index].ids = kept.map { columns[index].ids[$0] }
        }
        columns.removeAll { $0.ids.isEmpty }
        let known = Set(ids)
        var slot = focus.flatMap(column(of:)).map { $0 + 1 } ?? columns.count
        for id in tiled where !known.contains(id) {
            columns.insert(Column([id], width: width), at: slot)
            slot += 1
        }
    }

    mutating func replace(_ old: CGWindowID, with new: CGWindowID) {
        guard let index = column(of: old), let row = columns[index].ids.firstIndex(of: old) else { return }
        columns[index].ids[row] = new
    }

    mutating func remove(_ id: CGWindowID) {
        guard let index = column(of: id), let row = columns[index].ids.firstIndex(of: id) else { return }
        columns[index].ids.remove(at: row)
        columns[index].heights.remove(at: row)
        if columns[index].ids.isEmpty { columns.remove(at: index) }
    }

    mutating func moveColumn(of id: CGWindowID, by delta: Int) -> Bool {
        guard let index = column(of: id), columns.indices.contains(index + delta) else { return false }
        columns.swapAt(index, index + delta)
        return true
    }

    mutating func moveInColumn(_ id: CGWindowID, by delta: Int) -> Bool {
        guard let index = column(of: id), let row = columns[index].ids.firstIndex(of: id),
              columns[index].ids.indices.contains(row + delta) else { return false }
        columns[index].ids.swapAt(row, row + delta)
        columns[index].heights.swapAt(row, row + delta)
        return true
    }

    mutating func consumeOrExpel(_ id: CGWindowID, by delta: Int) -> Bool {
        guard let index = column(of: id) else { return false }
        if columns[index].ids.count > 1 {
            let width = columns[index].width
            remove(id)
            columns.insert(Column([id], width: width), at: delta > 0 ? index + 1 : index)
            return true
        }
        let target = index + delta
        guard columns.indices.contains(target) else { return false }
        let height = columns[index].heights.first ?? 1
        columns.remove(at: index)
        let into = delta > 0 ? target - 1 : target
        columns[into].ids.append(id)
        columns[into].heights.append(height)
        return true
    }

    mutating func place(_ id: CGWindowID, at other: CGWindowID, below: Bool) -> Bool {
        guard id != other, column(of: id) != nil, column(of: other) != nil else { return false }
        remove(id)
        guard let index = column(of: other), let row = columns[index].ids.firstIndex(of: other) else { return false }
        columns[index].ids.insert(id, at: below ? row + 1 : row)
        columns[index].heights.insert(1, at: below ? row + 1 : row)
        return true
    }

    mutating func swap(_ first: CGWindowID, _ second: CGWindowID) {
        guard let one = column(of: first), let two = column(of: second),
              let i = columns[one].ids.firstIndex(of: first),
              let j = columns[two].ids.firstIndex(of: second) else { return }
        columns[one].ids[i] = second
        columns[two].ids[j] = first
    }

    mutating func setWidth(of id: CGWindowID, _ change: (CGFloat) -> CGFloat) {
        guard let index = column(of: id) else { return }
        let width = change(columns[index].width)
        columns[index].width = min(Self.widthRange.upperBound, max(Self.widthRange.lowerBound, width))
    }

    mutating func cycleWidth(of id: CGWindowID, presets: [CGFloat]) {
        guard let index = column(of: id), !presets.isEmpty else { return }
        let width = columns[index].width
        columns[index].width = presets.first { $0 > width + 0.01 } ?? presets[0]
    }

    mutating func setHeight(of id: CGWindowID, by delta: CGFloat) {
        guard let index = column(of: id), let row = columns[index].ids.firstIndex(of: id),
              columns[index].ids.count > 1 else { return }
        let total = columns[index].heights.reduce(0, +)
        let share = columns[index].heights[row] / total
        let wanted = min(0.9, max(0.1, share + delta))
        let others = total - columns[index].heights[row]
        columns[index].heights[row] = wanted * others / (1 - wanted)
    }

    func columnFrames(in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let view = rect.insetBy(dx: -gap / 2, dy: -gap / 2)
        var x = view.minX - offset
        return columns.map { column in
            let width = (view.width * column.width).rounded()
            defer { x += width }
            return CGRect(x: x, y: view.minY, width: width, height: view.height)
        }
    }

    func frames(in rect: CGRect, gap: CGFloat) -> [CGWindowID: CGRect] {
        var out: [CGWindowID: CGRect] = [:]
        for (column, frame) in zip(columns, columnFrames(in: rect, gap: gap)) {
            let total = column.heights.reduce(0, +)
            var y = frame.minY
            for (id, weight) in zip(column.ids, column.heights) {
                let height = id == column.ids.last ? frame.maxY - y : (frame.height * weight / total).rounded()
                out[id] = CGRect(x: frame.minX, y: y, width: frame.width, height: height)
                    .insetBy(dx: gap / 2, dy: gap / 2).pixelAligned
                y += height
            }
        }
        return out
    }

    mutating func reveal(_ id: CGWindowID?, in rect: CGRect, gap: CGFloat, scroll: Scroll, centerSingle: Bool) {
        let view = rect.insetBy(dx: -gap / 2, dy: -gap / 2)
        let spans = columnFrames(in: rect, gap: gap).map { $0.offsetBy(dx: offset - view.minX, dy: 0) }
        let total = spans.last?.maxX ?? 0
        if columns.count == 1, centerSingle {
            offset = ((total - view.width) / 2).rounded()
            return
        }
        guard let index = id.flatMap(column(of:)) else {
            offset = min(max(0, total - view.width), max(0, offset))
            return
        }
        let span = spans[index]
        if scroll == .center || span.width >= view.width {
            offset = span.width >= view.width ? span.minX : (span.midX - view.width / 2).rounded()
            return
        }
        if span.minX < offset { offset = span.minX }
        if span.maxX > offset + view.width { offset = span.maxX - view.width }
        offset = min(max(0, total - view.width), max(0, offset))
    }
}
