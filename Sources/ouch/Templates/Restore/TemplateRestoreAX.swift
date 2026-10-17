import AppKit

enum TemplateRestoreAX {
    struct App: Sendable {
        var pid: pid_t
        var bundleID: String
        var launchDate: Date?
    }

    struct Candidate: @unchecked Sendable {
        var id: CGWindowID
        var element: AXUIElement
        var pid: pid_t
        var title: String
        var document: String?
        var launchDate: Date?
    }

    struct Probe: @unchecked Sendable {
        var id: CGWindowID
        var element: AXUIElement
    }

    static func invalidated(_ probes: [Probe], deadline: Date) async -> Set<CGWindowID> {
        await Task.detached(priority: .userInitiated) {
            var invalid = Set<CGWindowID>()
            for probe in probes {
                guard Date() < deadline else { break }
                var role: CFTypeRef?
                if AXUIElementCopyAttributeValue(probe.element, kAXRoleAttribute as CFString, &role) == .invalidUIElement {
                    invalid.insert(probe.id)
                }
            }
            return invalid
        }.value
    }

    static func read(apps: [App], deadline: Date) async -> [Candidate] {
        let stop = TemplateStopFlag()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                var found: [Candidate] = []
                for app in apps {
                    guard !stop.isStopped, Date() < deadline else { break }
                    let elements = axApp(app.pid).elements(kAXWindowsAttribute)
                    for element in elements {
                        guard !stop.isStopped, Date() < deadline else { break }
                        AXUIElementSetMessagingTimeout(element, axTimeout)
                        let subrole = element.string(kAXSubroleAttribute)
                        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
                              let id = element.windowID else { continue }
                        guard !stop.isStopped, Date() < deadline else { break }
                        let minimized = element.bool(kAXMinimizedAttribute) == true
                        guard TemplateWindowKind.includes(subrole: subrole, minimized: minimized) else { continue }
                        guard !stop.isStopped, Date() < deadline else { break }
                        let title = element.string(kAXTitleAttribute) ?? ""
                        guard !stop.isStopped, Date() < deadline else { break }
                        let document = TemplateWindowMatch.document(element)
                        guard !stop.isStopped, Date() < deadline else { break }
                        found.append(.init(id: id, element: element, pid: app.pid, title: title, document: document,
                                           launchDate: app.launchDate))
                    }
                }
                return found
            }.value
        } onCancel: { stop.stop() }
    }

    static func newWindow(pid: pid_t, deadline: Date) async -> Bool {
        let stop = TemplateStopFlag()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                let end = min(deadline, Date().addingTimeInterval(1.5))
                func expired() -> Bool { stop.isStopped || Date() >= end }
                guard !expired(), let bar = axApp(pid).element(kAXMenuBarAttribute) else { return false }
                AXUIElementSetMessagingTimeout(bar, axTimeout)
                var fallback: AXUIElement?
                for top in bar.elements(kAXChildrenAttribute) {
                    guard !expired() else { return false }
                    AXUIElementSetMessagingTimeout(top, axTimeout)
                    for menu in top.elements(kAXChildrenAttribute) {
                        guard !expired() else { return false }
                        AXUIElementSetMessagingTimeout(menu, axTimeout)
                        for item in menu.elements(kAXChildrenAttribute) {
                            guard !expired() else { return false }
                            AXUIElementSetMessagingTimeout(item, axTimeout)
                            guard item.bool(kAXEnabledAttribute) != false, !expired() else { continue }
                            if item.string(kAXTitleAttribute) == "New Window" {
                                guard !expired() else { return false }
                                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                            }
                            guard !expired() else { return false }
                            let command = item.string(kAXMenuItemCmdCharAttribute)
                            guard command?.lowercased() == "n", !expired() else { continue }
                            let modifiers = (item.value(kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue
                            if TemplateNewWindowCommand.isPlainCommandN(command: command, modifiers: modifiers) { fallback = item }
                        }
                    }
                }
                guard !expired(), let fallback else { return false }
                return AXUIElementPerformAction(fallback, kAXPressAction as CFString) == .success
            }.value
        } onCancel: { stop.stop() }
    }
}
