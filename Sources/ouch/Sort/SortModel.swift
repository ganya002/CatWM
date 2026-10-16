import AppKit
import SwiftUI


enum SortZone: Hashable {
    case lane(UUID), add, close, display(String), row(CGWindowID), scroller
}

struct SortNotice {
    var text: String
    var undo: (display: String, plan: SortPlan)?
}

struct SortReveal: Equatable {
    var id: CGWindowID = 0
    var lane: UUID?
    var token = 0
}

struct SortDrag {
    let item: SortItem
    let closing: Bool
    var location: CGPoint
    let grab: CGSize
    var id: CGWindowID { item.id }
}

struct SortColumnDrag {
    let lane: SortLane
    let ratio: CGFloat
    let mainCount: Int
    var location: CGPoint
    let grab: CGSize
}

final class SortModel: ObservableObject {
    @Published private(set) var displays: [SortDisplay] = []
    @Published private(set) var current = ""
    @Published private(set) var plans: [String: SortPlan] = [:]
    @Published var hover: CGWindowID?
    @Published var selected: CGWindowID?
    @Published var notice: SortNotice?
    @Published var nextLayout: Layout = .tall
    @Published var drag: SortDrag?
    @Published var columnDrag: SortColumnDrag?
    @Published var over: SortZone?
    @Published var columnSlot: Int?
    @Published var reveal = SortReveal()
    @Published var focusName: UUID?
    @Published var moreToRight = false
    @Published var shown = false
    var motion = PanelMotion.current

    var layouts: [Layout] = [.tall]
    var strategy: SortStrategy = .task
    var maxRows = 7
    var zones: [SortZone: CGRect] = [:]
    var finish: (String?) -> Void = { _ in }
    var revert: () -> Void = {}
    var changed: () -> Void = {}
    weak var scroller: NSScrollView?
    private var binds: [UInt64: KeyBinding] = [:]
    private var edgeTimer: Timer?
    private var scrollObserver: Any?
    private var running = false


    func begin(displays: [SortDisplay], start: String, config: Config) {
        self.displays = displays
        layouts = config.layouts.isEmpty ? [.tall] : config.layouts
        strategy = config.sortStrategy
        nextLayout = layouts.contains(.tall) ? .tall : layouts[0]
        plans = [:]
        hover = nil; selected = nil; notice = nil; drag = nil; columnDrag = nil; over = nil; columnSlot = nil; focusName = nil
        running = true
        binds = [:]
        var modes: [String] = []
        for b in config.bindings where !b.submap.isEmpty && !modes.contains(b.submap) { modes.append(b.submap) }
        let mode = modes.first { $0.lowercased() == "window" } ?? modes.first ?? ""
        for b in config.bindings where b.submap == mode { binds[Self.key(b.keyCode, b.mods)] = b }
        use(start)
    }

    private static func key(_ code: UInt16, _ mods: CGEventFlags) -> UInt64 {
        mods.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).rawValue | UInt64(code)
    }

    func end() {
        running = false
        edgeTimer?.invalidate()
        edgeTimer = nil
        if let o = scrollObserver { NotificationCenter.default.removeObserver(o) }
        scrollObserver = nil
        scroller = nil
        drag = nil; columnDrag = nil; over = nil; columnSlot = nil; hover = nil
    }


    var plan: SortPlan {
        plans[current] ?? SortPlan(display: current, items: [:], lanes: [], strategy: nil, existing: [], taken: [], active: nil)
    }

    var currentDisplay: SortDisplay? { displays.first { $0.id == current } }
    func display(_ uuid: String) -> SortDisplay? { displays.first { $0.id == uuid } }

    func count(of uuid: String) -> Int { plans[uuid]?.items.count ?? display(uuid)?.items.count ?? 0 }

    private func ensurePlan(_ uuid: String, grouped: Bool) {
        guard plans[uuid] == nil, let d = display(uuid) else { return }
        if grouped && !d.isSorted {
            var p = SortPlan.grouped(d, by: strategy, layouts: layouts, avoiding: reserved(excluding: uuid))
            p.touched = true
            p.pending = true
            plans[uuid] = p
        } else {
            plans[uuid] = .current(of: d)
        }
    }

    func reserved(excluding uuid: String? = nil) -> Set<String> {
        Set(plans.filter { $0.key != (uuid ?? current) }.values.flatMap { $0.lanes.map(\.ws) })
    }

    var nextName: String? { plan.canAdd(avoiding: reserved()) ? plan.available(avoiding: reserved()).first : nil }

    func use(_ uuid: String) {
        guard display(uuid) != nil else { return }
        current = uuid
        ensurePlan(uuid, grouped: true)
        selected = nil; hover = nil; notice = nil
        scrollToStart()
        if plans[uuid]?.pending == true { changed() }
    }

    func cycleDisplay(_ delta: Int) {
        guard displays.count > 1, let i = displays.firstIndex(where: { $0.id == current }) else { return }
        use(displays[((i + delta) % displays.count + displays.count) % displays.count].id)
    }

    func edit(keepNotice: Bool = false, _ change: (inout SortPlan) -> Void) {
        guard var p = plans[current] else { return }
        change(&p)
        p.touched = true
        p.pending = true
        plans[current] = p
        if !keepNotice { notice = nil }
        changed()
    }

    func pick(_ s: SortStrategy) {
        strategy = s
        let other = reserved()
        edit { $0.sort(by: s, layouts: layouts, avoiding: other) }
        selected = nil
        scrollToStart()
    }

    func closeDuplicates() { edit { $0.closeDuplicates() } }

    func rename(_ lane: UUID, _ name: String) {
        edit(keepNotice: true) { p in
            if let i = p.lanes.firstIndex(where: { $0.id == lane }) { p.lanes[i].name = name }
        }
    }

    func renumber(_ lane: UUID, to text: String) {
        let p = plan
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let i = p.lanes.firstIndex(where: { $0.id == lane }), !t.isEmpty, t != p.lanes[i].ws else { return }
        guard t.allSatisfy(\.isASCII), let n = Int(t), (1...SortPlan.maxLanes).contains(n) else {
            notice = SortNotice(text: "Workspace numbers run from 1 to \(SortPlan.maxLanes).", undo: nil)
            return
        }
        let ws = String(n)
        if p.taken.contains(ws) || reserved().contains(ws) {
            notice = SortNotice(text: "Workspace \(ws) is on another display.", undo: nil)
        } else if let held = p.lanes.first(where: { $0.ws == ws }), !held.ids.isEmpty || !held.name.trimmingCharacters(in: .whitespaces).isEmpty {
            notice = SortNotice(text: "Workspace \(ws) is in use. Move its windows away first.", undo: nil)
        } else {
            edit { $0.renumberLane(i, to: ws) }
            reveal = SortReveal(id: 0, lane: lane, token: reveal.token + 1)
        }
    }

    func pendingApplies() -> [SortApply] {
        let others = displays.map(\.id).filter { $0 != current }.compactMap { plans[$0] }.filter(\.pending)
        return (others + [plans[current]].compactMap { $0 }.filter(\.pending)).map(\.applied)
    }

    func markApplied() {
        for (k, p) in plans where p.pending {
            plans[k]?.pending = false
            plans[k]?.claimed.formUnion(p.lanes.map(\.ws))
        }
    }

    func result() -> (changed: Bool, closing: [CGWindowID], workspaces: Int) {
        let edited = plans.values.filter(\.touched)
        return (!edited.isEmpty, edited.flatMap(\.close), edited.reduce(0) { $0 + $1.lanes.filter { !$0.ids.isEmpty }.count })
    }

    func prune(alive: Set<CGWindowID>) {
        for k in plans.keys {
            guard var p = plans[k] else { continue }
            let gone = p.items.keys.filter { !alive.contains($0) }
            guard !gone.isEmpty else { continue }
            for id in gone { p.detach(id); p.items[id] = nil }
            plans[k] = p
            if let s = selected, gone.contains(s) { selected = nil }
            if let h = hover, gone.contains(h) { hover = nil }
        }
    }


    private func target() -> CGWindowID? { hover ?? selected }

    func place(_ id: CGWindowID, inLane i: Int, at index: Int? = nil) {
        edit { $0.place(id, inLane: i, at: index) }
        show(id)
    }

    func markClosing(_ id: CGWindowID) {
        edit { $0.markClosing(id) }
        show(id)
    }

    func toggleClose(_ id: CGWindowID) { plan.isClosing(id) ? restore(id) : markClosing(id) }

    func send(_ id: CGWindowID, toWorkspace ws: String) {
        if let i = plan.lanes.firstIndex(where: { $0.ws == ws }) {
            place(id, inLane: i)
        } else if let new = addLane(focus: false, named: ws) {
            place(id, inLane: new)
        }
    }

    @discardableResult
    func addLane(focus: Bool, named: String? = nil) -> Int? {
        var index: Int?
        let other = reserved()
        edit { index = $0.addLane(layout: nextLayout, named: named, avoiding: other) }
        guard let index else { return nil }
        let id = plan.lanes[index].id
        reveal = SortReveal(id: 0, lane: id, token: reveal.token + 1)
        if focus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.focusName = id } }
        return index
    }

    func cycleLayout(of lane: Int, by delta: Int = 1) { edit { $0.cycleLayout(of: lane, by: delta, in: layouts) } }

    func cycleNextLayout(by delta: Int = 1) {
        let i = layouts.firstIndex(of: nextLayout) ?? -1
        nextLayout = layouts[((i + delta) % layouts.count + layouts.count) % layouts.count]
    }

    func closeLane(_ id: UUID) {
        guard var p = plans[current], p.lanes.count > 1, let i = p.lanes.firstIndex(where: { $0.id == id }) else { return }
        let before = p, title = p.title(of: i)
        guard let n = p.closeLane(at: i) else { return }
        p.touched = true
        p.pending = true
        plans[current] = p
        changed()
        notice = SortNotice(text: n > 0 ? "Closing \(title). Its \(n) window\(n == 1 ? "" : "s") will close when you finish." : "Removed \(title).",
                            undo: (current, before))
    }

    func restore(_ id: CGWindowID) {
        let other = reserved()
        edit { $0.restore(id, avoiding: other) }
        show(id)
    }

    func reopen(_ group: UUID) {
        let other = reserved()
        edit { $0.reopen(group, avoiding: other) }
    }

    func removeLane(_ i: Int) {
        guard var p = plans[current], p.lanes.count > 1, p.lanes.indices.contains(i) else { return }
        let before = p, title = p.title(of: i)
        guard let r = p.removeLane(at: i) else { return }
        p.touched = true
        p.pending = true
        plans[current] = p
        changed()
        notice = SortNotice(text: r.moved > 0 ? "Removed \(title). Its \(r.moved) window\(r.moved == 1 ? "" : "s") moved to \(p.lanes[r.target].ws)."
                                              : "Removed \(title).", undo: (current, before))
    }

    func mergeLane(_ id: UUID, into target: UUID) {
        guard var p = plans[current], let i = p.lanes.firstIndex(where: { $0.id == id }),
              let j = p.lanes.firstIndex(where: { $0.id == target }) else { return }
        let before = p, title = p.title(of: i)
        guard let r = p.mergeLane(i, into: j) else { return }
        p.touched = true
        p.pending = true
        plans[current] = p
        changed()
        reveal = SortReveal(id: 0, lane: target, token: reveal.token + 1)
        notice = SortNotice(text: r.moved > 0 ? "Merged \(title) into \(p.title(of: r.target)). \(r.moved) window\(r.moved == 1 ? "" : "s") moved."
                                              : "Removed \(title).", undo: (current, before))
    }

    func moveLane(_ id: UUID, toSlot slot: Int) {
        guard let i = plan.lanes.firstIndex(where: { $0.id == id }) else { return }
        var at: Int?
        edit { at = $0.moveLane(i, toSlot: slot) }
        guard at != nil else { return }
        reveal = SortReveal(id: 0, lane: id, token: reveal.token + 1)
    }

    func undoRemove() {
        guard let u = notice?.undo else { return }
        var restored = u.plan
        for (i, lane) in restored.lanes.enumerated() {
            if let now = plans[u.display]?.lanes.first(where: { $0.id == lane.id }) { restored.lanes[i].name = now.name }
        }
        plans[u.display] = restored
        plans[u.display]?.touched = true
        plans[u.display]?.pending = true
        notice = nil
        changed()
    }

    func nudge(_ id: CGWindowID, _ d: Direction) {
        let p = plan
        switch d {
        case .up, .down:
            edit { $0.reorder(id, by: d == .up ? -1 : 1) }
            show(id)
        case .left, .right:
            let zone = p.lane(of: id) ?? p.lanes.count
            let next = zone + (d == .left ? -1 : 1)
            guard next >= 0, next <= p.lanes.count else { return }
            let list = zone < p.lanes.count ? p.lanes[zone].ids : p.close
            let pos = list.firstIndex(of: id) ?? 0
            if next == p.lanes.count {
                markClosing(id)
            } else {
                place(id, inLane: next, at: min(pos, p.lanes[next].ids.count))
            }
        }
    }

    func moveToTop(_ id: CGWindowID) {
        edit { $0.moveToTop(id) }
        show(id)
    }

    func moveToDisplay(_ id: CGWindowID, _ uuid: String) {
        guard uuid != current, var src = plans[current], let item = src.items[id], let to = display(uuid) else { return }
        ensurePlan(uuid, grouped: false)
        guard var dst = plans[uuid] else { return }
        src.detach(id)
        src.items[id] = nil
        src.touched = true
        src.pending = true
        dst.items[id] = item
        dst.touched = true
        dst.pending = true
        let lane = dst.activeLane
        dst.place(id, inLane: lane)
        plans[current] = src
        plans[uuid] = dst
        if selected == id { selected = nil }
        if hover == id { hover = nil }
        let name = dst.lanes[lane].name.trimmingCharacters(in: .whitespaces)
        changed()
        notice = SortNotice(text: "Moved \(item.title) to \(to.short), \(name.isEmpty ? "workspace \(dst.lanes[lane].ws)" : name).", undo: nil)
    }

    func moveSelection(_ d: Direction) {
        let p = plan
        let zones = p.lanes.map(\.ids) + [p.close]
        guard let cur = selected, let zi = zones.firstIndex(where: { $0.contains(cur) }), let pos = zones[zi].firstIndex(of: cur) else {
            selected = zones.first { !$0.isEmpty }?.first
            if let s = selected { show(s) }
            return
        }
        switch d {
        case .up, .down:
            let j = pos + (d == .up ? -1 : 1)
            if zones[zi].indices.contains(j) { selected = zones[zi][j] }
        case .left, .right:
            let step = d == .left ? -1 : 1
            var k = zi + step
            while zones.indices.contains(k) {
                if !zones[k].isEmpty { selected = zones[k][min(pos, zones[k].count - 1)]; break }
                k += step
            }
        }
        if let s = selected { show(s) }
    }

    func show(_ id: CGWindowID) {
        reveal = SortReveal(id: id, lane: plan.lane(of: id).map { plan.lanes[$0].id } ?? nil, token: reveal.token + 1)
    }


    private static let digits: [UInt16: Int] = Dictionary(uniqueKeysWithValues: (0...9).compactMap { n in
        keyCodes["\(n)"].map { ($0, n == 0 ? 10 : n) }
    })

    func handle(code: UInt16, mods: CGEventFlags, characters: String) -> Bool {
        let t = target()
        if let b = binds[Self.key(code, mods)], run(b, on: t) { return true }
        if let t, mods.isEmpty, let n = Self.digits[code] { send(t, toWorkspace: String(n)); return true }
        if mods.subtracting(.maskShift).isEmpty, characters == "+" || code == 69 || (characters == "=" && code == 24) {
            let new = addLane(focus: t == nil)
            if let t, let new { place(t, inLane: new) }
            return true
        }
        guard let t, mods.isEmpty else { return false }
        if [51, 117, 7].contains(code) { toggleClose(t); return true }
        return false
    }

    private func run(_ b: KeyBinding, on t: CGWindowID?) -> Bool {
        let arg = b.arg.trimmingCharacters(in: .whitespaces).lowercased()
        let p = plan
        switch b.dispatcher {
        case "movefocus":
            guard let d = Direction(arg) else { return false }
            if let hover { nudge(hover, d) } else { moveSelection(d) }
            return true
        case "movewindow", "swapwindow", "movewindowtomonitor":
            let spec = b.dispatcher == "movewindowtomonitor" ? arg : arg.hasPrefix("mon:") ? String(arg.dropFirst(4)) : nil
            if let spec {
                guard let t else { return false }
                let delta = spec.hasPrefix("-") || spec == "l" || spec == "u" ? -1 : 1
                guard displays.count > 1, let i = displays.firstIndex(where: { $0.id == current }) else { return true }
                moveToDisplay(t, displays[((i + delta) % displays.count + displays.count) % displays.count].id)
                return true
            }
            guard let t, let d = Direction(arg) else { return false }
            nudge(t, d)
            return true
        case "movetoworkspace", "movetoworkspacesilent":
            guard let t else { return false }
            let rel = arg.replacingOccurrences(of: "e", with: "").replacingOccurrences(of: "r", with: "").replacingOccurrences(of: "m", with: "")
            if (arg.hasPrefix("e") || arg.hasPrefix("r") || arg.hasPrefix("m") || arg.hasPrefix("+") || arg.hasPrefix("-")), let d = Int(rel.replacingOccurrences(of: "+", with: "")) {
                let cur = p.lane(of: t) ?? p.lanes.count
                let j = cur + d
                if p.lanes.indices.contains(j) { place(t, inLane: j) }
                return true
            }
            guard let n = Int(arg) else { return false }
            send(t, toWorkspace: String(n))
            return true
        case "cyclelayout":
            guard let t, let l = p.lane(of: t) else { return false }
            cycleLayout(of: l, by: arg.hasPrefix("prev") ? -1 : 1)
            return true
        case "layoutmsg":
            guard arg == "swapwithmaster", let t, p.lane(of: t) != nil else { return false }
            moveToTop(t)
            return true
        case "focusmonitor":
            cycleDisplay(arg.hasPrefix("-") ? -1 : 1)
            return true
        case "killactive":
            guard let t else { return false }
            toggleClose(t)
            return true
        default:
            return false
        }
    }


    func dragChanged(_ item: SortItem, _ v: DragGesture.Value) {
        if drag == nil {
            let origin = zones[.row(item.id)]?.origin ?? CGPoint(x: v.startLocation.x - 80, y: v.startLocation.y - 15)
            drag = SortDrag(item: item, closing: plan.isClosing(item.id), location: v.location,
                            grab: CGSize(width: v.startLocation.x - origin.x, height: v.startLocation.y - origin.y))
            hover = item.id
            startEdgeTimer()
        }
        drag?.location = v.location
        let zone = zone(at: v.location)
        let source = plan.lane(of: item.id).map { SortZone.lane(plan.lanes[$0].id) } ?? (plan.isClosing(item.id) ? .close : nil)
        let next = zone == source || (zone == .add && nextName == nil) ? nil : zone
        if over != next { over = next }
    }

    private func startEdgeTimer() {
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
        switch landing {
        case .display(let uuid): moveToDisplay(d.id, uuid)
        case .close: if !plan.isClosing(d.id) { markClosing(d.id) }
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

    private func columnTarget(_ id: UUID, at p: CGPoint) -> (over: SortZone?, slot: Int?) {
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

    private func zone(at p: CGPoint) -> SortZone? {
        for (z, f) in zones { if case .display = z, f.contains(p) { return z } }
        if let f = zones[.close], f.contains(p) { return .close }
        guard let s = zones[.scroller], s.contains(p) else { return nil }
        if let f = zones[.add], f.contains(p) { return .add }
        for (z, f) in zones { if case .lane = z, f.minX <= p.x, p.x < f.maxX { return z } }
        return nil
    }

    private func edgeScroll() {
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
