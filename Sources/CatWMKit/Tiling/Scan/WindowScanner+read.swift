import AppKit

extension WindowScanner {
    package static func read(_ job: Job, discovered: (AppScan) -> Void) -> AppScan {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var scan = AppScan()
        if job.listWindows {
            let known = Dictionary(job.known.values.map { ($0.element, $0.id) },
                                   uniquingKeysWith: { first, _ in first })
            var seen = Set<CGWindowID>()
            let entries = listedElements(axApp(job.pid)).compactMap { element -> (CGWindowID, AXUIElement)? in
                guard let id = known[element] ?? element.windowID, seen.insert(id).inserted else { return nil }
                AXUIElementSetMessagingTimeout(element, axTimeout)
                return (id, element)
            }
            scan.listed = entries.map(\.0)
            for (id, element) in entries where job.known[id] == nil { readNew(element, id: id, into: &scan) }
            if !job.known.isEmpty, scan.hasNewWindows(comparedTo: job.known) {
                var discovery = scan
                discovery.fullscreen.formUnion(job.fullscreen)
                discovery.minimized.formUnion(job.minimized)
                discovered(discovery)
            }
            for (id, _) in entries {
                if let known = job.known[id] { readKnown(known, into: &scan) }
            }
        }
        let listed = Set(scan.listed)
        for (id, window) in job.known where !listed.contains(id) {
            var role: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(window.element, kAXRoleAttribute as CFString, &role)
            if result == .invalidUIElement {
                scan.gone.insert(id)
            } else if result == .success {
                readKnown(window, into: &scan)
            }
        }
        return scan
    }

    private static func readNew(_ element: AXUIElement, id: CGWindowID, into scan: inout AppScan) {
        let attributes = WindowAttributes.read(element)
        if attributes.fullscreen { scan.fullscreen.insert(id) }
        if attributes.minimized { scan.minimized.insert(id) }
        guard attributes.subrole == kAXStandardWindowSubrole,
              !scan.minimized.contains(id) else { return }
        scan.found[id] = Found(element: element, frame: attributes.frame, title: attributes.title,
                               resizable: element.isSettable(kAXSizeAttribute))
    }

    package static func listedElements(_ app: AXUIElement,
                                       value: (AXUIElement, String) -> CFTypeRef? = { $0.value($1) }) -> [AXUIElement] {
        let listed = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return listed + (value(app, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            + [value(app, kAXMainWindowAttribute), value(app, kAXFocusedWindowAttribute)].compactMap {
                guard let result = $0, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
                return unsafeDowncast(result, to: AXUIElement.self)
            }
    }

    private static func readKnown(_ window: Window, into scan: inout AppScan) {
        let revision = window.frameRevision
        let attributes = WindowAttributes.read(window.element)
        if attributes.fullscreen { scan.fullscreen.insert(window.id) }
        if attributes.minimized { scan.minimized.insert(window.id) }
        scan.found[window.id] = Found(element: window.element, frame: attributes.frame, title: attributes.title,
                                      resizable: window.element.isSettable(kAXSizeAttribute), frameRevision: revision)
    }
}
