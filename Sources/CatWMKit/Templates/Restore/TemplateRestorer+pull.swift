import AppKit

extension TemplateRestorer {
    package struct Found {
        package var window: Window
        package var bundleID: String
        package var title: String
        package var document: String?
        package var launchDate: Date?
        package var allowsGenericFallback: Bool
        package var frame: CGRect?
    }

    package func currentDesktop() -> UInt64? {
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

    package func isFillable(_ candidate: Found) -> Bool {
        let id = candidate.window.id
        return pulled.contains(id) || (candidate.allowsGenericFallback && manager.workspaceOf[id] == nil)
            || initialWindowIDs.map { !$0.contains(id) } ?? false
    }

    package func pullOffDesktopWindows() async {
        guard let here = currentDesktop() else { return }
        let desktops = desktopSpaces()
        let list = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements])
        for bundle in Set(template.windows.map(\.bundleID)).sorted() {
            let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
                .map(\.processIdentifier))
            var present = 0
            var elsewhere: [(id: CGWindowID, space: UInt64)] = []
            for window in list where pids.contains(window.pid)
                && window.bounds.width >= 100 && window.bounds.height >= 100 {
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

    package func returnUnusedPulls(keeping used: some Collection<CGWindowID>) async {
        let used = Set(used)
        for (id, origin) in pullOrigins where !used.contains(id) && Spaces.of(window: id) != [origin] {
            Log.info("template: returning unused window \(id) to Desktop \(origin)")
            await move(id, to: origin)
        }
        pullOrigins = [:]
    }

    package func pullNewWindowsHere() {
        guard let initial = initialWindowIDs, let here = currentDesktop() else { return }
        let desktops = desktopSpaces()
        let pids = Set(template.windows.flatMap { saved in
            NSRunningApplication.runningApplications(withBundleIdentifier: saved.bundleID)
                .map(\.processIdentifier)
        })
        let list = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements])
        for window in list where pids.contains(window.pid) && !initial.contains(window.id)
            && !pulled.contains(window.id) && window.bounds.width >= 100 && window.bounds.height >= 100 {
            let membership = Spaces.of(window: window.id)
            if let space = membership.first {
                guard membership.count == 1, space != here, desktops.contains(space) else { continue }
            }
            pulled.insert(window.id)
            Log.info("template: pulling new window \(window.id) from Desktop \(membership) to \(here)")
            Spaces.move(window: window.id, to: here) { _ in }
        }
    }

    package func prepareMatchedEarly() {
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
