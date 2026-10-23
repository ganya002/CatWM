import AppKit

extension WindowManager {
    static let tabTitleBand: CGFloat = 44

    var tabs: TabGroups { model.tabs }

    func tabCommand(_ dispatcher: String, _ arg: String) {
        guard let window = focusedWindow() else { return }
        switch dispatcher {
        case "moveintogroup":
            guard let direction = Direction(arg), !window.isFloating else { return }
            let candidates = order.filter { visible.contains($0) && !tabs.isBehind($0) && $0 != window.id }
                .compactMap { windows[$0] }.filter { !$0.isFloating }
            guard case let .window(host) = resolve(direction, from: window, among: candidates) else { return }
            joinTab(window.id, onto: host.id)
        case "moveoutofgroup":
            untab(window.id)
        case "changegroupactive":
            let lowered = arg.lowercased()
            let offset = lowered.hasPrefix("b") || lowered.hasPrefix("prev") ? -1 : 1
            if let index = Int(lowered), let members = tabs.group(of: window.id)?.members,
               members.indices.contains(index - 1) {
                selectTab(members[index - 1])
            } else if let next = tabs.neighbor(of: window.id, offset: offset) {
                selectTab(next)
            }
        default: break
        }
    }

    func joinTab(_ id: CGWindowID, onto host: CGWindowID) {
        guard id != host, let window = windows[id], windows[host]?.isFloating == false,
              let workspace = workspaceOf[host] else { return }
        if window.isFloating {
            window.userFloating = .chosen(false)
            floatZoom[id] = nil
        }
        if workspaceOf[id] != workspace { assignManagedWindow(id, to: workspace) }
        if sharesSpaces, let display = displayOf[host] { displayOf[id] = display }
        let zoomed = screen(of: windows[host] ?? window).map(state(for:)).flatMap { $0.zoomed == host ? $0 : nil }
        model.joinTab(id, onto: host)
        if let zoomed { zoomed.zoomed = id }
        Log.info("tabs: \(window.bundleID ?? "window \(id)") joined the tabs of \(host)")
        corrections[id] = nil
        refresh()
        focus(window, warp: false)
    }

    func untab(_ id: CGWindowID, droppedAt point: CGPoint? = nil) {
        guard tabs.isGrouped(id), let window = windows[id] else { return }
        if let point, let host = tabDropTarget(for: id, at: point) {
            joinTab(id, onto: host)
            return
        }
        let heir = tabs.group(of: id).flatMap { $0.active == id ? tabs.neighbor(of: id, offset: 1) : $0.active }
        if let heir, let home = screen(of: window).map(state(for:)), home.zoomed == id { home.zoomed = heir }
        model.leaveTab(id)
        Log.info("tabs: \(window.bundleID ?? "window \(id)") left its tabs")
        refresh()
        focus(window, warp: false)
    }

    func selectTab(_ id: CGWindowID) {
        guard let window = windows[id], let group = tabs.group(of: id) else { return }
        activateTab(id, previous: group.active)
        focus(window, warp: false)
    }

    func reorderTab(_ id: CGWindowID, to position: Int) {
        model.tabs.move(id, to: position)
        TabStrips.shared.update()
    }

    private func activateTab(_ id: CGWindowID, previous: CGWindowID, retile: Bool = true) {
        guard id != previous else { return }
        if let home = windows[previous].flatMap({ screen(of: $0) }).map(state(for:)), home.zoomed == previous {
            home.zoomed = id
        }
        model.activateTab(id)
        if retile { refresh() }
    }

    func followTabFocus(_ id: CGWindowID?) {
        guard let id, let group = tabs.group(of: id), group.active != id, visible.contains(id) else {
            TabStrips.shared.update()
            return
        }
        activateTab(id, previous: group.active)
    }

    func settleTabs() {
        guard !tabs.isEmpty else { return }
        for group in tabs.groups {
            for member in group.members where windows[member]?.isFloating != false {
                model.leaveTab(member)
            }
        }
        for group in tabs.groups where !visible.contains(group.active) {
            guard let shown = group.members.first(where: visible.contains) else { continue }
            activateTab(shown, previous: group.active, retile: false)
        }
    }

    func tabStack(behind id: CGWindowID) -> [CGWindowID] {
        guard let group = tabs.group(of: id), group.active == id else { return [] }
        return group.members.filter {
            $0 != id && visible.contains($0) && windows[$0]?.isFloating == false && !workspaceMoves.contains($0)
        }
    }

    func belowTabStrip(_ slot: CGRect, for id: CGWindowID) -> CGRect {
        guard tabs.isGrouped(id) else { return slot }
        let inset = TabStrip.height
        return CGRect(x: slot.minX, y: slot.minY + inset, width: slot.width, height: max(0, slot.height - inset))
    }

    func slotMinimum(_ id: CGWindowID) -> CGSize? {
        guard let group = tabs.group(of: id) else { return minSizes[id] }
        let sizes = group.members.compactMap { minSizes[$0] }
        guard !sizes.isEmpty else { return nil }
        return CGSize(width: sizes.map(\.width).max() ?? 0,
                      height: (sizes.map(\.height).max() ?? 0) + TabStrip.height)
    }

    func tabDropTarget(for id: CGWindowID, at point: CGPoint) -> CGWindowID? {
        guard tilingEnabled, let screen = Screen.all().first(where: { $0.frame.contains(point) }) else { return nil }
        return tiled(on: screen).first { host in
            guard host != id, tabs.group(of: host)?.members.contains(id) != true,
                  let slot = targets[host] else { return false }
            return tabDropZone(host, slot).contains(point)
        }
    }

    func tabDropZone(_ host: CGWindowID, _ slot: CGRect) -> CGRect {
        let top = tabs.isGrouped(host) ? slot.minY - TabStrip.height : slot.minY
        return CGRect(x: slot.minX, y: top, width: slot.width, height: slot.minY - top + Self.tabTitleBand)
    }

    func updateTabDropHint() {
        guard let (id, resized) = drags.first, drags.count == 1, !resized,
              let window = windows[id], NSEvent.pressedMouseButtons & 1 != 0 else {
            TabDropHint.shared.hide()
            return
        }
        let point = mouseLocation()
        guard holds(window, at: point), let host = tabDropTarget(for: id, at: point), let slot = targets[host] else {
            TabDropHint.shared.hide()
            return
        }
        TabDropHint.shared.show(over: tabDropZone(host, slot).union(slot), adding: window)
    }

    func holds(_ window: Window, at point: CGPoint) -> Bool {
        window.cachedFrame.insetBy(dx: -8, dy: -8).contains(point)
    }

    func tabTitleChanged(_ element: AXUIElement) {
        guard !tabs.isEmpty, let window = windows.values.first(where: { CFEqual($0.element, element) }),
              tabs.isGrouped(window.id) else { return }
        scanner.run(window.pid) {
            let title = element.string(kAXTitleAttribute)
            DispatchQueue.main.async {
                window.title = title
                TabStrips.shared.update()
            }
        }
    }
}
