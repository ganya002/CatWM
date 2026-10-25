import AppKit

extension WindowManager {
    static let tabTitleBand: CGFloat = 44
    static let minimizeHold: TimeInterval = 2
    static let tabHoverDelay: TimeInterval = 0.4
    static let tabDragSlack: CGFloat = 40
    static let tabFollowWindow: TimeInterval = 1

    var tabs: TabGroups { model.tabs }

    func joinTab(_ id: CGWindowID, onto host: CGWindowID) {
        guard id != host, let window = windows[id], windows[host]?.isFloating == false,
              let workspace = workspaceOf[host] else { return }
        if window.isFloating {
            window.userFloating = .chosen(false)
            floats.floatZoom[id] = nil
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

    func joinTabs(of id: CGWindowID, onto host: CGWindowID) {
        guard let workspace = workspaceOf[host], windows[host]?.isFloating == false else { return }
        for member in tabs.group(of: id)?.members ?? [] where member != id {
            if workspaceOf[member] != workspace { assignManagedWindow(member, to: workspace) }
            if sharesSpaces, let display = displayOf[host] { displayOf[member] = display }
            model.joinTab(member, onto: host)
        }
        joinTab(id, onto: host)
    }

    func dropIntoStrip(_ id: CGWindowID, group: Int, at index: Int, alone: Bool = false) {
        guard let host = tabs.groups.first(where: { $0.id == group })?.active else { return refresh() }
        corrections = [:]
        if alone { joinTab(id, onto: host) } else { joinTabs(of: id, onto: host) }
        reorderTab(id, to: index)
    }

    func assignTabs(of id: CGWindowID, to workspace: String?) {
        moveTabs(of: id, to: workspace) { member, _ in assignManagedWindow(member, to: workspace) }
    }

    func untab(_ id: CGWindowID, droppedAt point: CGPoint? = nil) {
        guard tabs.isGrouped(id), let window = windows[id] else { return }
        let hit = point.flatMap(tiledSlotOwner(at:)).flatMap { config.mouseSwapsWindows && $0 != id ? $0 : nil }
        let heir = tabs.group(of: id).flatMap { $0.active == id ? tabs.heir(of: id) : $0.active }
        if let heir, let home = screen(of: window).map(state(for:)), home.zoomed == id { home.zoomed = heir }
        model.leaveTab(id)
        if let hit { swapOrder(id, hit) }
        Log.info("tabs: \(window.bundleID ?? "window \(id)") left its tabs")
        refresh()
        focus(window, warp: false)
    }

    func selectTab(_ id: CGWindowID) {
        guard let window = windows[id], let group = tabs.group(of: id) else { return }
        activateTab(id, previous: group.active)
        focus(window, warp: false)
    }

    func moveTab(_ id: CGWindowID, by offset: Int) {
        guard let members = tabs.group(of: id)?.members, let index = members.firstIndex(of: id),
              members.indices.contains(index + offset) else { return }
        reorderTab(id, to: index + offset)
    }

    func reorderTab(_ id: CGWindowID, to position: Int) {
        model.tabs.move(id, to: position)
        TabStrips.shared.update()
        saveTilingRecovery()
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
        guard tabUI.draggedTab == nil, let id, let group = tabs.group(of: id), group.active != id,
              visible.contains(id) else {
            TabStrips.shared.update()
            return
        }
        tabUI.tabFollow = (group.active, Date())
        activateTab(id, previous: group.active)
    }

    func settleTabs() {
        dropHiddenOnClose()
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

    func minimizeTabs(_ members: [CGWindowID]) {
        guard let group = members.first.flatMap(tabs.group(of:)) else { return }
        tabUI.minimizingTabs.insert(group.id)
        TabStrips.shared.update(instant: true)
        group.members.compactMap { windows[$0] }.forEach(minimize)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.minimizeHold) { [weak self] in
            self?.tabUI.minimizingTabs.remove(group.id)
            TabStrips.shared.update()
        }
    }

    func restoreTabGroup(of id: CGWindowID) {
        guard let group = tabs.group(of: id) else { return }
        if group.active != id, windows[group.active]?.minimized == true {
            model.activateTab(id)
        } else if tabs.isBehind(id), let active = windows[group.active], !active.minimized {
            scanner.run(active.pid) { active.element.perform(kAXRaiseAction) }
        }
        for member in group.members where member != id {
            guard let window = windows[member], window.minimized else { continue }
            scanner.run(window.pid) { window.element.set(kAXMinimizedAttribute, kCFBooleanFalse) }
        }
    }

    func dragTabGroup(_ window: Window) {
        guard let group = tabs.group(of: window.id), group.active == window.id, let slot = targets[window.id],
              !window.cachedFrame.isNull else { return }
        let offset = CGVector(dx: window.cachedFrame.minX - slot.minX, dy: window.cachedFrame.minY - slot.minY)
        let travelled = abs(offset.dx) + abs(offset.dy)
        let screens = Screen.all()
        for member in group.members where member != window.id && !tabUI.parkedTabs.contains(member) {
            guard let tab = windows[member], !tab.minimized, !tab.isFloating,
                  tab.pid != window.pid || travelled > Self.tabDragSlack else { continue }
            tabUI.parkedTabs.insert(member)
            cornerPark(member, screens: screens)
        }
        let top = screen(of: window, in: screens)?.visible.minY ?? slot.minY
        TabStripFollow.shared.follow(group.id, at: offset, lowest: top - slot.minY)
    }

    func settleParkedTabs() {
        TabStripFollow.shared.end()
        guard !tabUI.parkedTabs.isEmpty else { return }
        let parked = tabUI.parkedTabs
        tabUI.parkedTabs = []
        refresh()
        let actives = Set(parked.compactMap { tabs.group(of: $0)?.active }).compactMap { windows[$0] }
        animator.afterPendingWrites(pids: Set(parked.compactMap { windows[$0]?.pid })) { [weak self] in
            guard let self else { return }
            for active in actives { scanner.run(active.pid) { active.element.perform(kAXRaiseAction) } }
        }
    }

    func dragTab(_ id: CGWindowID, grab: CGPoint, to point: CGPoint) {
        guard let window = windows[id], let slot = targets[id] else { return }
        let held = CGRect(origin: CGPoint(x: point.x - grab.x, y: point.y - grab.y), size: slot.size)
        if tabUI.draggedTab != id {
            tabUI.draggedTab = id
            tabUI.tabDropCancelled = false
            focus(window, warp: false)
            animator.animate([.init(window: window, to: held, bounds: held)],
                             duration: config.animate ? config.animationDuration : 0,
                             curve: config.animationCurve, bounce: config.animationBounce)
        } else if !animator.retarget(window, to: held) {
            animator.position(window, at: held)
        }
        guard !tabUI.tabDropCancelled else { return }
        guard !TabStrips.shared.preview(window, at: point) else {
            trackTabHover(nil)
            return TabDropHint.shared.hide()
        }
        trackTabHover(for: id, at: point)
        showTabDropHint(adding: window, onto: tabDropTarget(for: id, at: point) ?? settledTabHover(for: id, at: point))
    }

    private func returnTab(_ id: CGWindowID) {
        if tabs.group(of: id)?.active == id { refresh() } else { selectTab(id) }
    }

    private func sharesTabs(_ host: CGWindowID, _ id: CGWindowID) -> Bool {
        host == id || tabs.group(of: host)?.members.contains(id) == true
    }

    func dropTab(_ id: CGWindowID, at point: CGPoint) {
        let joins = !tabUI.tabDropCancelled
        let hovered = joins ? settledTabHover(for: id, at: point) : nil
        tabUI.draggedTab = nil
        tabUI.tabDropCancelled = false
        TabDropHint.shared.hide()
        trackTabHover(nil)
        let previewed = TabStrips.shared.endPreview(of: id)
        if !joins {
            untab(id, droppedAt: point)
        } else if let previewed {
            Log.info("tabs: \(id) dropped into the strip of group \(previewed.group) at \(previewed.index)")
            dropIntoStrip(id, group: previewed.group, at: previewed.index, alone: true)
        } else if let host = tabDropTarget(for: id, at: point) ?? hovered {
            if sharesTabs(host, id) { returnTab(id) } else { joinTab(id, onto: host) }
        } else {
            untab(id, droppedAt: point)
        }
        TabStrips.shared.update()
    }

    func cancelTabDrag(_ id: CGWindowID) {
        guard tabUI.draggedTab == id else { return }
        tabUI.draggedTab = nil
        tabUI.tabDropCancelled = false
        trackTabHover(nil)
        TabDropHint.shared.hide()
        _ = TabStrips.shared.endPreview(of: id)
        returnTab(id)
    }

    func showHeir(of id: CGWindowID, focused: Bool) {
        let replaced = tabUI.tabFollow.map {
            $0.previous == id && Date().timeIntervalSince($0.at) < Self.tabFollowWindow
        }
        guard focused || replaced == true,
              let heir = tabs.group(of: id).flatMap({ $0.active == id || replaced == true ? tabs.heir(of: id) : nil })
        else { return }
        tabUI.tabFollow = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.windows[heir] else { return }
            if self.tabs.isGrouped(heir) { self.selectTab(heir) } else { self.focus(window, warp: false) }
        }
    }

    func covered(_ tab: Window, by target: CGRect) -> Bool {
        let frame = animator.destination(tab.id) ?? tab.cachedFrame
        return !frame.isNull && target.contains(frame)
    }

    func tabStack(behind id: CGWindowID) -> [CGWindowID] {
        guard let group = tabs.group(of: id), group.active == id else { return [] }
        return group.members.filter {
            $0 != id && visible.contains($0) && windows[$0]?.isFloating == false && !workspaceMoves.contains($0)
        }
    }

    func stackTabs(_ tiles: [CGWindowID: CGRect]) -> [CGWindowID: CGRect] {
        var slots: [CGWindowID: CGRect] = [:]
        for (id, tile) in tiles {
            let slot = belowTabStrip(tile, for: id)
            let behind = tabs.group(of: id)?.members.filter { $0 != id && windows[$0]?.isFloating == false } ?? []
            for member in [id] + behind { slots[member] = slot }
        }
        return slots
    }

    func belowTabStrip(_ slot: CGRect, for id: CGWindowID) -> CGRect {
        guard let group = tabs.group(of: id),
              !config.autoHideTabStrip || TabStripReveal.shared.revealed == group.id else { return slot }
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
        tabHost(for: id, at: point) { host, slot in tabDropZone(host, slot) }
    }

    func tiledSlotOwner(at point: CGPoint) -> CGWindowID? {
        guard tilingEnabled, let screen = Screen.all().first(where: { $0.frame.contains(point) }) else { return nil }
        return tiled(on: screen).first { targets[$0]?.contains(point) == true }
    }

    func settledTabHover(for id: CGWindowID, at point: CGPoint) -> CGWindowID? {
        guard let hover = tabUI.tabHover, hover.settled else { return nil }
        let owner = tiledSlotOwner(at: point) ?? hover.host
        return owner == hover.host && (owner != id || tabUI.draggedTab == id) ? hover.host : nil
    }

    private func tabHost(for id: CGWindowID, at point: CGPoint,
                         zone: (CGWindowID, CGRect) -> CGRect) -> CGWindowID? {
        guard tilingEnabled, let screen = Screen.all().first(where: { $0.frame.contains(point) }) else { return nil }
        return tiled(on: screen).first { host in
            guard host != id, tabs.group(of: host)?.members.contains(id) != true,
                  let slot = targets[host] else { return false }
            return zone(host, slot).contains(point)
        }
    }

    private func trackTabHover(for id: CGWindowID, at point: CGPoint) {
        guard let owner = tiledSlotOwner(at: point) else { return }
        trackTabHover(tabUI.draggedTab == id || !sharesTabs(owner, id) ? owner : nil)
    }

    func trackTabHover(_ host: CGWindowID?) {
        guard host != tabUI.tabHover?.host else { return }
        tabUI.tabHoverWork?.cancel()
        tabUI.tabHoverWork = nil
        tabUI.tabHover = host.map { ($0, false) }
        guard let host else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.tabUI.tabHover?.host == host else { return }
            self.tabUI.tabHover?.settled = true
            self.updateTabDropHint()
        }
        tabUI.tabHoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tabHoverDelay, execute: work)
    }

    func tabDropZone(_ host: CGWindowID, _ slot: CGRect) -> CGRect {
        let top = tabs.isGrouped(host) ? slot.minY - TabStrip.height : slot.minY
        return CGRect(x: slot.minX, y: top, width: slot.width, height: slot.minY - top + Self.tabTitleBand)
    }

    func updateTabDropHint() {
        guard !tabUI.tabDropCancelled else { return TabDropHint.shared.hide() }
        if let id = tabUI.draggedTab, let window = windows[id] {
            let point = mouseLocation()
            return showTabDropHint(adding: window,
                                   onto: tabDropTarget(for: id, at: point) ?? settledTabHover(for: id, at: point))
        }
        guard let (id, resized) = drags.first, drags.count == 1, !resized,
              let window = windows[id], NSEvent.pressedMouseButtons & 1 != 0 else {
            TabDropHint.shared.hide()
            return
        }
        let point = mouseLocation()
        guard !TabStrips.shared.preview(window, at: point) else {
            trackTabHover(nil)
            return TabDropHint.shared.hide()
        }
        trackTabHover(for: id, at: point)
        let band = holds(window, at: point) ? tabDropTarget(for: id, at: point) : nil
        showTabDropHint(adding: window, onto: band ?? settledTabHover(for: id, at: point))
    }

    private func showTabDropHint(adding window: Window, onto host: CGWindowID?) {
        guard let host, let slot = targets[host] else { return TabDropHint.shared.hide() }
        TabDropHint.shared.show(over: tabDropZone(host, slot).union(slot), adding: window)
    }

    func holds(_ window: Window, at point: CGPoint) -> Bool {
        window.cachedFrame.insetBy(dx: -8, dy: -8).contains(point)
    }

    func titleChanged(_ element: AXUIElement) {
        guard !tabs.isEmpty || Notifications.shared.enabled,
              let window = windows.values.first(where: { CFEqual($0.element, element) }) else { return }
        let grouped = tabs.isGrouped(window.id)
        guard grouped || Notifications.shared.enabled else { return }
        scanner.run(window.pid) {
            let title = element.string(kAXTitleAttribute)
            DispatchQueue.main.async {
                guard window.title != title else { return }
                window.title = title
                Notifications.shared.titleChanged(window)
                if grouped { TabStrips.shared.update() }
            }
        }
    }
}
