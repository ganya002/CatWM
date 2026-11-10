import AppKit

package enum RestoreAX {
    package struct App: Sendable {
        package var pid: pid_t
        package var bundleID: String
        package var launchDate: Date?

        package init(pid: pid_t, bundleID: String, launchDate: Date?) {
            self.pid = pid
            self.bundleID = bundleID
            self.launchDate = launchDate
        }
    }

    package struct Candidate: @unchecked Sendable { // style-ok: AXUIElement is safe to use on any thread
        package var id: CGWindowID
        package var element: AXUIElement
        package var pid: pid_t
        package var title: String
        package var document: String?
        package var launchDate: Date?
        package var frame: CGRect?
    }

    package struct Probe: @unchecked Sendable { // style-ok: AXUIElement is safe to use on any thread
        package var id: CGWindowID
        package var element: AXUIElement

        package init(id: CGWindowID, element: AXUIElement) {
            self.id = id
            self.element = element
        }
    }

    package static func invalidated(_ probes: [Probe], deadline: Date) async -> Set<CGWindowID> {
        await Task.detached(priority: .userInitiated) {
            var invalid = Set<CGWindowID>()
            for probe in probes {
                guard Date() < deadline else { break }
                var role: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(probe.element, kAXRoleAttribute as CFString, &role)
                if status == .invalidUIElement {
                    invalid.insert(probe.id)
                }
            }
            return invalid
        }.value
    }

    package static func read(apps: [App], deadline: Date) async -> (candidates: [Candidate], complete: Bool) {
        let stop = StopFlag()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                var found: [Candidate] = []
                func expired() -> Bool { stop.isStopped || Date() >= deadline }
                for app in apps {
                    guard !expired() else { return (found, false) }
                    let listed: [AXUIElement]
                    switch axApp(app.pid).readElements(kAXWindowsAttribute) {
                    case .stalled: return (found, false)
                    case .missing: continue
                    case .value(let elements): listed = elements
                    }
                    for element in listed {
                        guard !expired() else { return (found, false) }
                        switch candidate(element, app: app, expired: expired) {
                        case .stalled: return (found, false)
                        case .missing: continue
                        case .value(let window): found.append(window)
                        }
                    }
                }
                return (found, true)
            }.value
        } onCancel: { stop.stop() }
    }

    private static func candidate(_ element: AXUIElement, app: App, expired: () -> Bool) -> AXRead<Candidate> {
        AXUIElementSetMessagingTimeout(element, axTimeout)
        let subrole: String?
        switch element.readString(kAXSubroleAttribute) {
        case .stalled: return .stalled
        case .missing: subrole = nil
        case .value(let value): subrole = value
        }
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
              let id = element.windowNumber else { return .missing }
        guard !expired() else { return .stalled }
        let minimized = element.readBool(kAXMinimizedAttribute).value ?? false
        guard WindowKind.includes(subrole: subrole, minimized: minimized) else { return .missing }
        guard !expired() else { return .stalled }
        let title: String
        switch element.readString(kAXTitleAttribute) {
        case .stalled: return .stalled
        case .missing: title = ""
        case .value(let value): title = value
        }
        guard !expired() else { return .stalled }
        let document: String?
        switch element.readString(kAXDocumentAttribute) {
        case .stalled: return .stalled
        case .missing: document = nil
        case .value(let raw): document = DocumentURL.normalized(raw)
        }
        guard !expired() else { return .stalled }
        let frame = element.readFrame().value
        guard !expired() else { return .stalled }
        return .value(Candidate(id: id, element: element, pid: app.pid, title: title, document: document,
                                launchDate: app.launchDate, frame: frame))
    }

    package static func newWindow(pid: pid_t, deadline: Date) async -> Bool {
        let stop = StopFlag()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                let end = min(deadline, Date().addingTimeInterval(1.5))
                func expired() -> Bool { stop.isStopped || Date() >= end }
                guard !expired(), let bar = axApp(pid).readElement(kAXMenuBarAttribute).value else {
                    return false
                }
                AXUIElementSetMessagingTimeout(bar, axTimeout)
                var fallback: AXUIElement?
                for top in children(bar) {
                    guard !expired() else { return false }
                    AXUIElementSetMessagingTimeout(top, axTimeout)
                    for menu in children(top) {
                        if case .finished(let result) = scan(menu, expired: expired, fallback: &fallback) {
                            return result
                        }
                    }
                }
                guard !expired(), let fallback else { return false }
                return fallback.press()
            }.value
        } onCancel: { stop.stop() }
    }

    private enum MenuItemCheck {
        case pressed(Bool)
        case expired
        case fallback
        case skip
    }

    private enum MenuScan {
        case finished(Bool)
        case next
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        element.readElements(kAXChildrenAttribute).value ?? []
    }

    private static func scan(_ menu: AXUIElement, expired: () -> Bool, fallback: inout AXUIElement?) -> MenuScan {
        guard !expired() else { return .finished(false) }
        AXUIElementSetMessagingTimeout(menu, axTimeout)
        for item in children(menu) {
            switch check(item, expired: expired) {
            case .pressed(let success): return .finished(success)
            case .expired: return .finished(false)
            case .fallback: fallback = item
            case .skip: continue
            }
        }
        return .next
    }

    private static func check(_ item: AXUIElement, expired: () -> Bool) -> MenuItemCheck {
        guard !expired() else { return .expired }
        AXUIElementSetMessagingTimeout(item, axTimeout)
        guard item.readBool(kAXEnabledAttribute).value ?? true, !expired() else { return .skip }
        if item.readString(kAXTitleAttribute).value == "New Window" {
            guard !expired() else { return .expired }
            return .pressed(item.press())
        }
        guard !expired() else { return .expired }
        let command = item.readString(kAXMenuItemCmdCharAttribute).value
        guard command?.lowercased() == "n", !expired() else { return .skip }
        let modifiers = item.read(kAXMenuItemCmdModifiersAttribute).value as? Int
        return NewWindowCommand.isPlainCommandN(command: command, modifiers: modifiers) ? .fallback : .skip
    }
}
