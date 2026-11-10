import AppKit
import CatWMKit
import SwiftUI

extension SortModel {
    func nudge(_ id: CGWindowID, _ direction: Direction) {
        let snapshot = plan
        switch direction {
        case .upward, .down:
            edit { $0.reorder(id, by: direction == .upward ? -1 : 1) }
            show(id)
        case .left, .right:
            let zone = snapshot.lane(of: id) ?? snapshot.lanes.count
            let next = zone + (direction == .left ? -1 : 1)
            guard next >= 0, next <= snapshot.lanes.count else { return }
            let list = zone < snapshot.lanes.count ? snapshot.lanes[zone].ids : snapshot.close
            let pos = list.firstIndex(of: id) ?? 0
            if next == snapshot.lanes.count {
                markClosing(id)
            } else {
                place(id, inLane: next, at: min(pos, snapshot.lanes[next].ids.count))
            }
        }
    }

    func moveToTop(_ id: CGWindowID) {
        edit { $0.moveToTop(id) }
        show(id)
    }

    func moveToDisplay(_ ids: [CGWindowID], _ uuid: String) {
        ids.forEach { moveToDisplay($0, uuid) }
        guard ids.count > 1, var dst = plans[uuid] else { return }
        ids.forEach { dst.untab($0) }
        dst.tabs.append(ids)
        dst.keepTabsTogether()
        plans[uuid] = dst
    }

    func moveToDisplay(_ id: CGWindowID, _ uuid: String) {
        guard uuid != current,
              var src = plans[current],
              let item = src.items[id],
              let destination = display(uuid) else { return }
        ensurePlan(uuid)
        guard var dst = plans[uuid] else { return }
        let lane = dst.activeLane
        src.untab(id)
        src.detach(id)
        src.items[id] = nil
        dst.untab(id)
        dst.items[id] = item
        dst.place(id, inLane: lane)
        src.touched = true
        src.pending = true
        dst.touched = true
        dst.pending = true
        plans[current] = src
        plans[uuid] = dst
        if selected == id { selected = nil }
        if hover == id { hover = nil }
        let name = dst.lanes[lane].name.trimmingCharacters(in: .whitespaces)
        changed()
        let laneName = name.isEmpty ? "workspace \(dst.lanes[lane].number)" : name
        notice = SortNotice(text: "Moved \(item.title) to \(destination.short), \(laneName).")
    }

    func moveSelection(_ direction: Direction) {
        let snapshot = plan
        let zones = snapshot.lanes.map(\.ids) + [snapshot.close]
        guard let cur = selected,
              let zoneIndex = zones.firstIndex(where: { $0.contains(cur) }),
              let pos = zones[zoneIndex].firstIndex(of: cur) else {
            selected = zones.first { !$0.isEmpty }?.first
            if let selected { show(selected) }
            return
        }
        switch direction {
        case .upward, .down:
            let j = pos + (direction == .upward ? -1 : 1)
            if zones[zoneIndex].indices.contains(j) { selected = zones[zoneIndex][j] }
        case .left, .right:
            let step = direction == .left ? -1 : 1
            var candidate = zoneIndex + step
            while zones.indices.contains(candidate) {
                if !zones[candidate].isEmpty {
                    selected = zones[candidate][min(pos, zones[candidate].count - 1)]
                    break
                }
                candidate += step
            }
        }
        if let selected { show(selected) }
    }

    func show(_ id: CGWindowID) {
        reveal = SortReveal(id: id, lane: plan.lane(of: id).map { plan.lanes[$0].id }, token: reveal.token + 1)
    }

    func handle(code: UInt16, mods: CGEventFlags, characters: String) -> Bool {
        let windowID = target()
        if let bind = binds[Self.key(code, mods)], run(bind, on: windowID) { return true }
        if let windowID, mods.isEmpty, let number = Self.digits[code] {
            send(windowID, toWorkspace: plan.key(String(number)))
            return true
        }
        if mods.subtracting(.maskShift).isEmpty, characters == "+" || code == 69 || (characters == "=" && code == 24) {
            let new = addLane(focus: windowID == nil)
            if let windowID, let new { place(windowID, inLane: new) }
            return true
        }
        guard let windowID, mods.isEmpty else { return false }
        if [51, 117, 7].contains(code) { toggleClose(windowID); return true }
        return false
    }

    func run(_ bind: KeyBinding, on windowID: CGWindowID?) -> Bool {
        let arg = bind.arg.trimmingCharacters(in: .whitespaces).lowercased()
        switch bind.dispatcher {
        case WindowActions.movefocus.name:
            guard let direction = Direction(arg) else { return false }
            if let hover { nudge(hover, direction) } else { moveSelection(direction) }
            return true
        case WindowActions.movewindow.name, WindowActions.swapwindow.name, WindowActions.movewindowtomonitor.name:
            return runMoveWindow(dispatcher: bind.dispatcher, arg: arg, on: windowID)
        case WindowActions.movetoworkspace.name, WindowActions.movetoworkspacesilent.name:
            return runMoveToWorkspace(arg: arg, on: windowID)
        case WindowActions.cyclelayout.name:
            guard let windowID, let lane = plan.lane(of: windowID) else { return false }
            cycleLayout(of: lane, by: arg.hasPrefix("prev") ? -1 : 1)
            return true
        case WindowActions.layoutmsg.name:
            guard arg == "swapwithmaster", let windowID, plan.lane(of: windowID) != nil else { return false }
            moveToTop(windowID)
            return true
        case WindowActions.focusmonitor.name:
            cycleDisplay(arg.hasPrefix("-") ? -1 : 1)
            return true
        case WindowActions.killactive.name:
            guard let windowID else { return false }
            toggleClose(windowID)
            return true
        default:
            return false
        }
    }

    private func runMoveWindow(dispatcher: String, arg: String, on windowID: CGWindowID?) -> Bool {
        let spec = dispatcher == WindowActions.movewindowtomonitor.name
            ? arg
            : arg.hasPrefix("mon:") ? String(arg.dropFirst(4)) : nil
        if let spec {
            guard let windowID else { return false }
            let delta = spec.hasPrefix("-") || spec == "l" || spec == "u" ? -1 : 1
            guard displays.count > 1, let i = displays.firstIndex(where: { $0.id == current }) else { return true }
            moveToDisplay(windowID, displays[((i + delta) % displays.count + displays.count) % displays.count].id)
            return true
        }
        guard let windowID, let direction = Direction(arg) else { return false }
        nudge(windowID, direction)
        return true
    }

    private func runMoveToWorkspace(arg: String, on windowID: CGWindowID?) -> Bool {
        guard let windowID else { return false }
        let snapshot = plan
        let rel = arg
            .replacingOccurrences(of: "e", with: "")
            .replacingOccurrences(of: "r", with: "")
            .replacingOccurrences(of: "m", with: "")
        let relative = ["e", "r", "m", "+", "-"].contains { arg.hasPrefix($0) }
        if relative, let delta = Int(rel.replacingOccurrences(of: "+", with: "")) {
            let cur = snapshot.lane(of: windowID) ?? snapshot.lanes.count
            let j = cur + delta
            if snapshot.lanes.indices.contains(j) { place(windowID, inLane: j) }
            return true
        }
        guard let number = Int(arg) else { return false }
        send(windowID, toWorkspace: plan.key(String(number)))
        return true
    }
}
