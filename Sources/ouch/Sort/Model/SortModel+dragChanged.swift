import AppKit
import SwiftUI

extension SortModel {
    func dragChanged(_ item: SortItem, _ v: DragGesture.Value) {
        if drag == nil {
            let origin = zones[.row(item.id)]?.origin ?? CGPoint(x: v.startLocation.x - 80, y: v.startLocation.y - 15)
            drag = SortDrag(item: item, closing: plan.isClosing(item.id), location: v.location,
                            grab: CGSize(width: min(max(v.startLocation.x - origin.x, 0), 160),
                                         height: min(max(v.startLocation.y - origin.y, 0), SortMetrics.rowHeight)))
            hover = item.id
            startEdgeTimer()
        }
        drag?.location = v.location
        let zone = zone(at: v.location)
        let source = plan.lane(of: item.id).map { SortZone.lane(plan.lanes[$0].id) } ?? (plan.isClosing(item.id) ? .close : nil)
        let landable: Bool = {
            guard unplacedFullscreen(item.id) != nil else { return true }
            if case .lane = zone { return true }
            return zone == .add
        }()
        let next = zone == source || (zone == .add && nextName == nil) || !landable ? nil : zone
        if over != next { over = next }
    }

    func startEdgeTimer() {
        let t = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.edgeScroll() }
        RunLoop.main.add(t, forMode: .common)
        edgeTimer = t
    }

    func dragEnded() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        guard let d = drag else { return }
        let landing = zone(at: d.location)
        drag = nil
        over = nil
        hover = nil
        let unplaced = unplacedFullscreen(d.id) != nil
        switch landing {
        case .display(let uuid): if !unplaced { moveToDisplay(d.id, uuid) }
        case .close: if !unplaced, !plan.isClosing(d.id) { markClosing(d.id) }
        case .add:
            if let new = addLane(focus: false) { place(d.id, inLane: new) }
        case .lane(let id):
            if let i = plan.lanes.firstIndex(where: { $0.id == id }), plan.lane(of: d.id) != i { place(d.id, inLane: i) }
        default: break
        }
    }

    func columnDragChanged(_ lane: SortLane, _ v: DragGesture.Value) {
        if columnDrag == nil {
            let origin = zones[.lane(lane.id)]?.origin ?? CGPoint(x: v.startLocation.x - 80, y: v.startLocation.y - 20)
            let g = plan.geometry[lane.ws]
            columnDrag = SortColumnDrag(lane: lane, ratio: g?.ratio ?? 0.5, mainCount: g?.mainCount ?? 1, location: v.location,
                                        grab: CGSize(width: v.startLocation.x - origin.x, height: v.startLocation.y - origin.y))
            startEdgeTimer()
        }
        columnDrag?.location = v.location
        let t = columnTarget(lane.id, at: v.location)
        if over != t.over { over = t.over }
        if columnSlot != t.slot { columnSlot = t.slot }
    }

    func columnDragEnded() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        guard let d = columnDrag else { return }
        let t = columnTarget(d.lane.id, at: d.location)
        columnDrag = nil
        over = nil
        columnSlot = nil
        switch (t.over, t.slot) {
        case (.close?, _): closeLane(d.lane.id)
        case (.lane(let target)?, _): withAnimation(Motion.easeOut) { mergeLane(d.lane.id, into: target) }
        case (nil, let slot?): withAnimation(Motion.spring) { moveLane(d.lane.id, toSlot: slot) }
        default: break
        }
    }

    func columnTarget(_ id: UUID, at p: CGPoint) -> (over: SortZone?, slot: Int?) {
        let z = zone(at: p)
        if z == .close { return (.close, nil) }
        let lanes = plan.lanes
        guard let from = lanes.firstIndex(where: { $0.id == id }) else { return (nil, nil) }
        func slot(_ s: Int) -> (SortZone?, Int?) { s == from || s == from + 1 ? (nil, nil) : (nil, s) }
        if z == .add { return slot(lanes.count) }
        guard let s = zones[.scroller], s.contains(p) else { return (nil, nil) }
        let frames = lanes.enumerated().compactMap { i, l in zones[.lane(l.id)].map { (i, l.id, $0) } }
        guard !frames.isEmpty else { return (nil, nil) }
        let edge: CGFloat = 36
        for (i, lid, f) in frames where f.minX - 2 <= p.x && p.x < f.maxX + 2 {
            if p.x < f.minX + edge { return slot(i) }
            if p.x >= f.maxX - edge { return slot(i + 1) }
            return lid == id ? (nil, nil) : (.lane(lid), nil)
        }
        return (nil, nil)
    }

    func zone(at p: CGPoint) -> SortZone? {
        for (z, f) in zones { if case .display = z, f.contains(p) { return z } }
        if let f = zones[.close], f.contains(p) { return .close }
        guard let s = zones[.scroller], s.contains(p) else { return nil }
        if let f = zones[.add], f.contains(p) { return .add }
        for (z, f) in zones { if case .lane = z, f.minX <= p.x, p.x < f.maxX { return z } }
        return nil
    }

    func edgeScroll() {
        guard let d = drag?.location ?? columnDrag?.location, let s = zones[.scroller], d.y > s.minY - 40, d.y < s.maxY + 40 else { return }
        let edge: CGFloat = 56, top: CGFloat = 14
        if d.x > s.maxX - edge, d.x <= s.maxX { scrollRow(by: 2 + top * (d.x - (s.maxX - edge)) / edge) }
        else if d.x < s.minX + edge { scrollRow(by: -(2 + top * min(1, (s.minX + edge - d.x) / edge))) }
    }

    func attach(_ scroll: NSScrollView?) {
        guard running, let scroll, scroller !== scroll else { return }
        scroller = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        if let o = scrollObserver { NotificationCenter.default.removeObserver(o) }
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                                                queue: .main) { [weak self] _ in self?.measureRow() }
        measureRow()
    }

    func measureRow() {
        guard let s = scroller, let doc = s.documentView else { return }
        let more = s.contentView.bounds.maxX < doc.frame.width - 2
        if more != moreToRight { moreToRight = more }
    }

    func scrollRow(by dx: CGFloat) {
        guard let s = scroller, let doc = s.documentView else { return }
        let clip = s.contentView
        var o = clip.bounds.origin
        o.x = max(0, min(o.x + dx, doc.frame.width - clip.bounds.width))
        clip.scroll(to: o)
        s.reflectScrolledClipView(clip)
    }

    func scrollToStart() {
        guard let s = scroller else { return }
        s.contentView.scroll(to: .zero)
        s.reflectScrolledClipView(s.contentView)
    }
}
