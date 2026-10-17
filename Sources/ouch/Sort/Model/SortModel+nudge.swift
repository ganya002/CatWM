import AppKit
import SwiftUI

extension SortModel {
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

    func run(_ b: KeyBinding, on t: CGWindowID?) -> Bool {
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

}
