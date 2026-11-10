import AppKit
import CatWMKit
import SwiftUI

extension SortModel {
    func dragChanged(_ item: SortItem, _ value: DragGesture.Value, group: Bool = false) {
        if drag == nil {
            let start = value.startLocation
            let key: SortZone = group ? .tabs(item.id) : .row(item.id)
            let origin = zones[key]?.origin ?? CGPoint(x: start.x - 80, y: start.y - 15)
            let closing = plan.isClosing(item.id)
            let members = group
                ? plan.tabs(of: item.id).filter { closing ? plan.isClosing($0) : plan.lane(of: $0) != nil }
                : []
            drag = SortDrag(item: item, closing: closing, location: value.location,
                            grab: CGSize(width: min(max(start.x - origin.x, 0), 160),
                                         height: min(max(start.y - origin.y, 0), SortMetrics.rowHeight)),
                            group: members.compactMap { plan.items[$0] })
            hover = item.id
            startEdgeTimer()
        }
        drag?.location = value.location
        let zone = dropZone(at: value.location)
        let source = plan.lane(of: item.id).map { SortZone.lane(plan.lanes[$0].id) }
            ?? (plan.isClosing(item.id) ? .close : nil)
        let landable: Bool = {
            guard unplacedFullscreen(item.id) != nil else { return true }
            if case .lane = zone { return true }
            return zone == .add
        }()
        let next = zone == source || (zone == .add && nextName == nil) || !landable ? nil : zone
        if over != next { over = next }
    }

    func dropZone(at point: CGPoint) -> SortZone? {
        guard let drag else { return zone(at: point) }
        for (zone, frame) in zones where frame.contains(point) {
            guard case .tabs(let lead) = zone, drag.group.isEmpty, unplacedFullscreen(drag.id) == nil,
                  !plan.tabs(of: lead).contains(drag.id) else { continue }
            return zone
        }
        return zone(at: point)
    }

    func startEdgeTimer() {
        edgeTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.edgeScroll() }
        RunLoop.main.add(timer, forMode: .common)
        edgeTimer = timer
    }

    func dragEnded() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        guard let ended = drag else { return }
        let landing = dropZone(at: ended.location)
        drag = nil
        over = nil
        hover = nil
        let unplaced = unplacedFullscreen(ended.id) != nil
        let ids = ended.group.isEmpty ? [ended.id] : ended.group.map(\.id)
        switch landing {
        case .display(let uuid): if !unplaced { moveToDisplay(ids, uuid) }
        case .close: if !unplaced { ids.filter { !plan.isClosing($0) }.forEach(markClosing) }
        case .tabs(let lead): joinTabs(ended.id, onto: lead)
        case .add:
            if let new = addLane(focus: false) { place(ended.id, inLane: new, tabs: !ended.group.isEmpty) }
        case .lane(let id):
            if let i = plan.lanes.firstIndex(where: { $0.id == id }), plan.lane(of: ended.id) != i {
                place(ended.id, inLane: i, tabs: !ended.group.isEmpty)
            }
        default: break
        }
    }

    func columnDragChanged(_ lane: SortLane, _ value: DragGesture.Value) {
        if columnDrag == nil {
            let start = value.startLocation
            let origin = zones[.lane(lane.id)]?.origin ?? CGPoint(x: start.x - 80, y: start.y - 20)
            let geometry = plan.geometry[lane.workspace]
            columnDrag = SortColumnDrag(lane: lane, ratio: geometry?.ratio ?? 0.5,
                                        mainCount: geometry?.mainCount ?? 1, location: value.location,
                                        grab: CGSize(width: start.x - origin.x, height: start.y - origin.y))
            startEdgeTimer()
        }
        columnDrag?.location = value.location
        let columnHit = columnTarget(lane.id, at: value.location)
        if over != columnHit.over { over = columnHit.over }
        if columnSlot != columnHit.slot { columnSlot = columnHit.slot }
    }

    func columnDragEnded() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        guard let ended = columnDrag else { return }
        let columnHit = columnTarget(ended.lane.id, at: ended.location)
        columnDrag = nil
        over = nil
        columnSlot = nil
        withAnimation(Motion.user) {
            switch (columnHit.over, columnHit.slot) {
            case (.close, _): closeLane(ended.lane.id)
            case (.lane(let target), _): mergeLane(ended.lane.id, into: target)
            case (nil, let slot?): moveLane(ended.lane.id, toSlot: slot)
            default: break
            }
        }
    }

    func columnTarget(_ id: UUID, at point: CGPoint) -> (over: SortZone?, slot: Int?) {
        let hit = zone(at: point)
        if hit == .close { return (.close, nil) }
        let lanes = plan.lanes
        guard let from = lanes.firstIndex(where: { $0.id == id }) else { return (nil, nil) }
        func slot(_ index: Int) -> (SortZone?, Int?) { index == from || index == from + 1 ? (nil, nil) : (nil, index) }
        if hit == .add { return slot(lanes.count) }
        guard let scrollFrame = zones[.scroller], scrollFrame.contains(point) else { return (nil, nil) }
        let frames = lanes.enumerated().compactMap { i, lane in zones[.lane(lane.id)].map { (i, lane.id, $0) } }
        guard !frames.isEmpty else { return (nil, nil) }
        let edge: CGFloat = 36
        for (i, laneID, frame) in frames where frame.minX - 2 <= point.x && point.x < frame.maxX + 2 {
            if point.x < frame.minX + edge { return slot(i) }
            if point.x >= frame.maxX - edge { return slot(i + 1) }
            return laneID == id ? (nil, nil) : (.lane(laneID), nil)
        }
        return (nil, nil)
    }

    var carriesToClose: Bool { columnDrag != nil || drag.map { !$0.closing } == true }

    var dragOutside: Bool {
        guard carriesToClose, let point = drag?.location ?? columnDrag?.location,
              let card = zones[.panel] else { return false }
        return !card.contains(point)
    }

    func zone(at point: CGPoint) -> SortZone? {
        for (zone, frame) in zones { if case .display = zone, frame.contains(point) { return zone } }
        if let frame = zones[.close], frame.contains(point) { return .close }
        if let frame = zones[.panel], !frame.contains(point) { return .close }
        guard let scrollFrame = zones[.scroller], scrollFrame.contains(point) else { return nil }
        if let frame = zones[.add], frame.contains(point) { return .add }
        for (zone, frame) in zones { if case .lane = zone, frame.minX <= point.x, point.x < frame.maxX { return zone } }
        return nil
    }

    func edgeScroll() {
        guard let location = drag?.location ?? columnDrag?.location,
              let frame = zones[.scroller],
              location.y > frame.minY - 40,
              location.y < frame.maxY + 40 else { return }
        let edge: CGFloat = 56, top: CGFloat = 14
        let right = min(frame.maxX, zones[.close]?.minX ?? frame.maxX)
        if location.x > right - edge, location.x <= right {
            scrollRow(by: 2 + top * (location.x - (right - edge)) / edge)
        } else if location.x < frame.minX + edge {
            scrollRow(by: -(2 + top * min(1, (frame.minX + edge - location.x) / edge)))
        }
    }

    func attach(_ scroll: NSScrollView?) {
        guard running, let scroll, scroller !== scroll else { return }
        scroller = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        if let observer = scrollObserver { NotificationCenter.default.removeObserver(observer) }
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                object: scroll.contentView,
                                                                queue: .main) { [weak self] _ in self?.measureRow() }
        measureRow()
    }

    func measureRow() {
        guard let scroller, let doc = scroller.documentView else { return }
        let more = scroller.contentView.bounds.maxX < doc.frame.width - 2
        if more != moreToRight { moreToRight = more }
    }

    func scrollRow(by dx: CGFloat) {
        guard let scroller, let doc = scroller.documentView else { return }
        let clip = scroller.contentView
        var origin = clip.bounds.origin
        origin.x = max(0, min(origin.x + dx, doc.frame.width - clip.bounds.width))
        clip.scroll(to: origin)
        scroller.reflectScrolledClipView(clip)
    }

    func scrollToStart() {
        guard let scroller else { return }
        scroller.contentView.scroll(to: .zero)
        scroller.reflectScrolledClipView(scroller.contentView)
    }
}
