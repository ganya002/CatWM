import AppKit

extension TemplateRestorer {
    struct Found {
        var window: Window
        var bundleID: String
        var title: String
        var document: String?
        var launchDate: Date?
        var allowsGenericFallback: Bool
        var frame: CGRect?
    }

    struct ListedWindow {
        var id: CGWindowID
        var pid: Int
        var size: CGSize

        var isLargeEnough: Bool { size.width >= 100 && size.height >= 100 }
    }

    nonisolated static func windowList(_ options: CGWindowListOption) -> [ListedWindow] {
        let list = CGWindowListCopyWindowInfo([options, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0, let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return ListedWindow(id: CGWindowID(truncatingIfNeeded: number), pid: pid,
                                size: CGSize(width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0))
        }
    }

    func currentDesktop() -> UInt64? {
        (manager.currentScreen() ?? Screen.all().first).map { Spaces.current(display: $0.uuid) }
    }

    private func desktopSpaces() -> Set<UInt64> {
        Set(Screen.all().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
    }

    private func move(_ id: CGWindowID, to space: UInt64) async {
        _ = await withCheckedContinuation { continuation in
            Spaces.move(window: id, to: space) { continuation.resume(returning: $0) }
        }
    }

    func isFillable(_ candidate: Found) -> Bool {
        let id = candidate.window.id
        return pulled.contains(id) || (candidate.allowsGenericFallback && manager.workspaceOf[id] == nil)
            || initialWindowIDs.map { !$0.contains(id) } ?? false
    }

    func pullOffDesktopWindows() async {
        guard let here = currentDesktop() else { return }
        let desktops = desktopSpaces()
        let list = Self.windowList(.optionAll)
        for bundle in Set(template.windows.map(\.bundleID)).sorted() {
            let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
                .map { Int($0.processIdentifier) })
            var present = 0
            var elsewhere: [(id: CGWindowID, space: UInt64)] = []
            for window in list where pids.contains(window.pid) && window.isLargeEnough {
                let membership = Spaces.of(window: window.id)
                if membership.contains(here) {
                    present += 1
                } else if membership.count == 1, let space = membership.first, desktops.contains(space) {
                    elsewhere.append((window.id, space))
                }
            }
            let wanted = template.windows.filter { $0.bundleID == bundle }.count
            for (id, origin) in elsewhere.prefix(max(0, wanted - present)) {
                guard !Task.isCancelled else { return }
                pulled.insert(id)
                pullOrigins[id] = origin
                Log.info("template: pulling window \(id) of \(bundle) from Desktop \(origin) to \(here)")
                await move(id, to: here)
            }
        }
    }

    func returnUnusedPulls(keeping used: some Collection<CGWindowID>) async {
        let used = Set(used)
        for (id, origin) in pullOrigins where !used.contains(id) && Spaces.of(window: id) != [origin] {
            Log.info("template: returning unused window \(id) to Desktop \(origin)")
            await move(id, to: origin)
        }
        pullOrigins = [:]
    }

    func pullNewWindowsHere() {
        guard let initial = initialWindowIDs, let here = currentDesktop() else { return }
        let desktops = desktopSpaces()
        let pids = Set(template.windows.flatMap { saved in
            NSRunningApplication.runningApplications(withBundleIdentifier: saved.bundleID)
                .map { Int($0.processIdentifier) }
        })
        for window in Self.windowList(.optionAll) where pids.contains(window.pid) && !initial.contains(window.id)
            && !pulled.contains(window.id) && window.isLargeEnough {
            let membership = Spaces.of(window: window.id)
            if let space = membership.first {
                guard membership.count == 1, space != here, desktops.contains(space) else { continue }
            }
            pulled.insert(window.id)
            Log.info("template: pulling new window \(window.id) from Desktop \(membership) to \(here)")
            Spaces.move(window: window.id, to: here) { _ in }
        }
    }

    func prepareMatchedEarly() {
        let screens = Screen.all()
        let mainID = NSScreen.screens.first?.displayID
        let mapping = template.displayMap(available: screens.map { ($0.uuid, $0.id == mainID) })
        for saved in template.windows where !saved.minimized && !saved.fullscreen {
            guard let window = matched[saved.id], earlyRestored.insert(window.id).inserted else { continue }
            AXUIElementSetMessagingTimeout(window.element, axTimeout)
            if window.element.flag(kAXMinimizedAttribute) {
                _ = window.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
            }
            guard initialWindowIDs?.contains(window.id) == false, !window.isNativeFullscreen,
                  let target = mapping[saved.display], let screen = screens.first(where: { $0.uuid == target }),
                  let original = template.displays.first(where: { $0.id == saved.display }) else { continue }
            window.setFrame(WorkspaceTemplate.restoredFrame(saved.frame, from: original.visible, to: screen.visible))
        }
    }
}
