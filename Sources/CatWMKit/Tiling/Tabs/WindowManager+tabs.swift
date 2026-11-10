import AppKit

extension WindowManager {
    package static let tabTitleBand: CGFloat = 44
    package static let minimizeHold: TimeInterval = 2
    package static let tabDragSlack: CGFloat = 40
    package static let tabFollowWindow: TimeInterval = 1

    package var tabs: TabGroups { model.tabs }

    package func joinTab(_ id: CGWindowID, onto host: CGWindowID) {
        guard config.features.contains(.tabGroups) else { return }
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

    package func joinTabs(of id: CGWindowID, onto host: CGWindowID) {
        guard let workspace = workspaceOf[host], windows[host]?.isFloating == false else { return }
        for member in tabs.group(of: id)?.members ?? [] where member != id {
            if workspaceOf[member] != workspace { assignManagedWindow(member, to: workspace) }
            if sharesSpaces, let display = displayOf[host] { displayOf[member] = display }
            model.joinTab(member, onto: host)
        }
        joinTab(id, onto: host)
    }

    package func dropIntoStrip(_ id: CGWindowID, group: Int, at index: Int, alone: Bool = false) {
        guard let host = tabs.groups.first(where: { $0.id == group })?.active else { return refresh() }
        corrections = [:]
        if alone { joinTab(id, onto: host) } else { joinTabs(of: id, onto: host) }
        reorderTab(id, to: index)
    }

    package func assignTabs(of id: CGWindowID, to workspace: String?) {
        moveTabs(of: id, to: workspace) { member, _ in assignManagedWindow(member, to: workspace) }
    }

    package func dissolveTabs() {
        tabUI.savedTabs = []
        let members = tabs.groups.flatMap { $0.members.dropFirst() }
        guard !members.isEmpty else { return }
        for id in members { model.leaveTab(id) }
        Log.info("tabs: tab groups are off, so \(members.count) window(s) left their tabs")
        surface.tabsDidChange(instant: true)
        refresh()
    }

    package func untab(_ id: CGWindowID, droppedAt point: CGPoint? = nil) {
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

    package func selectTab(_ id: CGWindowID) {
        guard let window = windows[id], let group = tabs.group(of: id) else { return }
        activateTab(id, previous: group.active)
        focus(window, warp: false)
    }

    package func moveTab(_ id: CGWindowID, by offset: Int) {
        guard let members = tabs.group(of: id)?.members, let index = members.firstIndex(of: id),
              members.indices.contains(index + offset) else { return }
        reorderTab(id, to: index + offset)
    }

    package func reorderTab(_ id: CGWindowID, to position: Int) {
        model.tabs.move(id, to: position)
        surface.tabsDidChange(instant: false)
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

    package func followTabFocus(_ id: CGWindowID?) {
        guard tabUI.drag.lifted == nil, let id, let group = tabs.group(of: id), group.active != id,
              visible.contains(id) else {
            surface.tabsDidChange(instant: false)
            return
        }
        tabUI.tabFollow = (group.active, Date())
        activateTab(id, previous: group.active)
    }

    package func settleTabs() {
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

    package func minimizeTabs(_ members: [CGWindowID]) {
        guard let group = members.first.flatMap(tabs.group(of:)) else { return }
        tabUI.minimizingTabs.insert(group.id)
        surface.tabsDidChange(instant: true)
        group.members.compactMap { windows[$0] }.forEach(minimize)
        DispatchQueue.main.asyncAfter( // style-ok: covers the minimize animation
            deadline: .now() + Self.minimizeHold
        ) { [weak self] in
            self?.tabUI.minimizingTabs.remove(group.id)
            self?.surface.tabsDidChange(instant: false)
        }
    }

    package func restoreTabGroup(of id: CGWindowID) {
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

    package func dragTabGroup(_ window: Window) {
        guard let group = tabs.group(of: window.id), group.active == window.id, let slot = targets[window.id],
              !window.cachedFrame.isNull else { return }
        let offset = CGVector(dx: window.cachedFrame.minX - slot.minX, dy: window.cachedFrame.minY - slot.minY)
        let travelled = abs(offset.dx) + abs(offset.dy)
        let screens = backend.screens()
        for member in group.members where member != window.id && !tabUI.parkedTabs.contains(member) {
            guard let tab = windows[member], !tab.minimized, !tab.isFloating,
                  tab.pid != window.pid || travelled > Self.tabDragSlack else { continue }
            tabUI.parkedTabs.insert(member)
            cornerPark(member, screens: screens)
        }
        let top = screen(of: window, in: screens)?.visible.minY ?? slot.minY
        surface.followTabStrip(group.id, at: offset, lowest: top - slot.minY)
    }

    package func settleParkedTabs() {
        surface.endTabStripFollow()
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

    package func dragTab(_ id: CGWindowID, grab: CGPoint, to point: CGPoint) {
        guard let window = windows[id], let slot = targets[id] else { return }
        let held = CGRect(origin: CGPoint(x: point.x - grab.x, y: point.y - grab.y), size: slot.size)
        if tabUI.drag.beginLifted(id) {
            focus(window, warp: false)
            animator.animate([.init(window: window, to: held, bounds: held)],
                             duration: config.animate ? config.animationDuration : 0,
                             curve: config.animationCurve, bounce: config.animationBounce)
        } else if !animator.retarget(window, to: held) {
            animator.position(window, at: held)
        }
        guard tabUI.drag.allowsJoin else { return }
        guard !surface.previewTabDrop(window, at: point) else {
            tabUI.drag.track(nil, changed: {})
            return surface.hideTabDropHint()
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

    package func dropTab(_ id: CGWindowID, at point: CGPoint) {
        let joins = tabUI.drag.allowsJoin
        let hovered = joins ? settledTabHover(for: id, at: point) : nil
        let completed = tabUI.drag.finish(id, on: surface)
        let previewed = completed.preview
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
        surface.tabsDidChange(instant: false)
    }

    package func cancelTabDrag(_ id: CGWindowID) {
        guard tabUI.drag.lifted == id else { return }
        tabUI.drag.finish(id, on: surface)
        returnTab(id)
    }

    package func showHeir(of id: CGWindowID, focused: Bool) {
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

    package func covered(_ tab: Window, by target: CGRect) -> Bool {
        let frame = animator.destination(tab.id) ?? tab.cachedFrame
        return !frame.isNull && target.contains(frame)
    }

    package func tabStack(behind id: CGWindowID) -> [CGWindowID] {
        guard let group = tabs.group(of: id), group.active == id else { return [] }
        return group.members.filter {
            $0 != id && visible.contains($0) && windows[$0]?.isFloating == false && !nativeMoves.isMoving($0)
        }
    }

    package func stackTabs(_ tiles: [CGWindowID: CGRect]) -> [CGWindowID: CGRect] {
        var slots: [CGWindowID: CGRect] = [:]
        for (id, tile) in tiles {
            let slot = belowTabStrip(tile, for: id)
            let behind = tabs.group(of: id)?.members.filter { $0 != id && windows[$0]?.isFloating == false } ?? []
            for member in [id] + behind { slots[member] = slot }
        }
        return slots
    }

    package func belowTabStrip(_ slot: CGRect, for id: CGWindowID) -> CGRect {
        guard let group = tabs.group(of: id),
              !config.autoHideTabStrip || surface.revealedTabGroup == group.id else { return slot }
        let inset = TabGeometry.stripHeight
        return CGRect(x: slot.minX, y: slot.minY + inset, width: slot.width, height: max(0, slot.height - inset))
    }

    package func slotMinimum(_ id: CGWindowID) -> CGSize? {
        guard let group = tabs.group(of: id) else { return minSizes[id] }
        let sizes = group.members.compactMap { minSizes[$0] }
        guard !sizes.isEmpty else { return nil }
        return CGSize(width: sizes.map(\.width).max() ?? 0,
                      height: (sizes.map(\.height).max() ?? 0) + TabGeometry.stripHeight)
    }

    package func tabDropTarget(for id: CGWindowID, at point: CGPoint) -> CGWindowID? {
        tabHost(for: id, at: point) { host, slot in tabDropZone(host, slot) }
    }

    package func tiledSlotOwner(at point: CGPoint) -> CGWindowID? {
        guard tilingEnabled, let screen = backend.screens().first(where: { $0.frame.contains(point) }) else {
            return nil
        }
        return tiled(on: screen).first { targets[$0]?.contains(point) == true }
    }

    package func settledTabHover(for id: CGWindowID, at point: CGPoint) -> CGWindowID? {
        guard let hover = tabUI.drag.hover, hover.settled else { return nil }
        let owner = tiledSlotOwner(at: point) ?? hover.host
        return owner == hover.host && (owner != id || tabUI.drag.lifted == id) ? hover.host : nil
    }

    private func tabHost(for id: CGWindowID, at point: CGPoint,
                         zone: (CGWindowID, CGRect) -> CGRect) -> CGWindowID? {
        guard tilingEnabled, let screen = backend.screens().first(where: { $0.frame.contains(point) }) else {
            return nil
        }
        return tiled(on: screen).first { host in
            guard host != id, tabs.group(of: host)?.members.contains(id) != true,
                  let slot = targets[host] else { return false }
            return zone(host, slot).contains(point)
        }
    }

    private func trackTabHover(for id: CGWindowID, at point: CGPoint) {
        guard let owner = tiledSlotOwner(at: point) else { return }
        tabUI.drag.track(tabUI.drag.lifted == id || !sharesTabs(owner, id) ? owner : nil) { [weak self] in
            self?.updateTabDropHint()
        }
    }

    package func tabDropZone(_ host: CGWindowID, _ slot: CGRect) -> CGRect {
        let top = tabs.isGrouped(host) ? slot.minY - TabGeometry.stripHeight : slot.minY
        return CGRect(x: slot.minX, y: top, width: slot.width, height: slot.minY - top + Self.tabTitleBand)
    }

    package func updateTabDropHint() {
        guard tabUI.drag.allowsJoin else { return surface.hideTabDropHint() }
        if let id = tabUI.drag.lifted, let window = windows[id] {
            let point = mouseLocation()
            return showTabDropHint(adding: window,
                                   onto: tabDropTarget(for: id, at: point) ?? settledTabHover(for: id, at: point))
        }
        guard let (id, resized) = drags.first, drags.count == 1, !resized,
              let window = windows[id], NSEvent.pressedMouseButtons & 1 != 0 else {
            surface.hideTabDropHint()
            return
        }
        let point = mouseLocation()
        guard !surface.previewTabDrop(window, at: point) else {
            tabUI.drag.track(nil, changed: {})
            return surface.hideTabDropHint()
        }
        trackTabHover(for: id, at: point)
        let band = holds(window, at: point) ? tabDropTarget(for: id, at: point) : nil
        showTabDropHint(adding: window, onto: band ?? settledTabHover(for: id, at: point))
    }

    private func showTabDropHint(adding window: Window, onto host: CGWindowID?) {
        guard let host, let slot = targets[host] else { return surface.hideTabDropHint() }
        surface.showTabDropHint(over: tabDropZone(host, slot).union(slot), adding: window)
    }

    package func holds(_ window: Window, at point: CGPoint) -> Bool {
        window.cachedFrame.insetBy(dx: -8, dy: -8).contains(point)
    }

    package func titleChanged(_ element: AXUIElement) {
        guard let window = windows.values.first(where: { CFEqual($0.element, element) }) else { return }
        let grouped = tabs.isGrouped(window.id)
        scanner.run(window.pid) {
            let title = element.string(kAXTitleAttribute)
            DispatchQueue.main.async {
                guard window.title != title else { return }
                let wasFloating = window.isFloating
                window.title = title
                if !self.tabs.isGrouped(window.id) {
                    window.autoFloating = self.shouldFloat(window, title: title,
                                                           resizable: window.resizable || window.fullscreen)
                }
                if wasFloating != window.isFloating {
                    self.corrections[window.id] = nil
                    self.scheduleRefresh()
                }
                self.surface.titleChanged(window)
                if grouped { self.surface.tabsDidChange(instant: false) }
            }
        }
    }
}
