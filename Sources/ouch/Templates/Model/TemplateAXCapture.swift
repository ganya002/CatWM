import AppKit
import ApplicationServices

enum TemplateAXCapture {
    static func collect(apps: [TemplateAppSnapshot], frontmostPID: pid_t?, budget: TimeInterval,
                        stop: @escaping @Sendable () -> Bool) -> TemplateWindowBatch {
        let deadline = Date().addingTimeInterval(budget)
        let expired: @Sendable () -> Bool = { stop() || Date() >= deadline }
        var batch = TemplateWindowWalk.collect(apps: apps, budget: budget, stop: expired) { app in
            read(app, deadline: deadline, stop: stop)
        }
        if batch.complete, let frontmostPID, !expired() {
            batch.focusedID = focusedID(frontmostPID)
        }
        return batch
    }

    private static func read(_ app: TemplateAppSnapshot, deadline: Date, stop: @escaping @Sendable () -> Bool) -> TemplateAppRead {
        if stop() || Date() >= deadline { return .stalled }
        let application = axApp(app.pid)
        let listed: [AXUIElement]
        switch elements(application, kAXWindowsAttribute) {
        case .stalled: return .stalled
        case .missing: return .windows([])
        case .value(let found): listed = found
        }
        var windows: [TemplateObservedWindow] = []
        for element in listed {
            if stop() || Date() >= deadline { return .stalled }
            AXUIElementSetMessagingTimeout(element, axTimeout)
            switch observe(element, app) {
            case .stalled: return .stalled
            case .skip: continue
            case .window(let window): windows.append(window)
            }
        }
        return .windows(windows)
    }

    private static func focusedID(_ pid: pid_t) -> CGWindowID? {
        let application = axApp(pid)
        switch element(application, kAXFocusedWindowAttribute) {
        case .stalled, .missing:
            return nil
        case .value(let focused):
            AXUIElementSetMessagingTimeout(focused, axTimeout)
            return focused.windowID
        }
    }

    private enum WindowRead {
        case window(TemplateObservedWindow)
        case skip
        case stalled
    }

    private static func observe(_ element: AXUIElement, _ app: TemplateAppSnapshot) -> WindowRead {
        let subrole: String
        switch string(element, kAXSubroleAttribute) {
        case .stalled: return .stalled
        case .missing: return .skip
        case .value(let value): subrole = value
        }
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
              let id = element.windowID else { return .skip }
        let minimized: Bool
        switch bool(element, kAXMinimizedAttribute) {
        case .stalled: return .stalled
        case .missing: minimized = false
        case .value(let flag): minimized = flag
        }
        guard TemplateWindowKind.includes(subrole: subrole, minimized: minimized) else { return .skip }
        let fullscreen: Bool
        switch bool(element, "AXFullScreen") {
        case .stalled: return .stalled
        case .missing: fullscreen = false
        case .value(let flag): fullscreen = flag
        }
        let title: String
        switch string(element, kAXTitleAttribute) {
        case .stalled: return .stalled
        case .missing: title = ""
        case .value(let text): title = text
        }
        let document: String?
        switch string(element, kAXDocumentAttribute) {
        case .stalled: return .stalled
        case .missing: document = nil
        case .value(let raw): document = documentURL(raw)
        }
        let resizable: Bool
        switch settable(element, kAXSizeAttribute) {
        case .stalled: return .stalled
        case .missing: resizable = false
        case .value(let flag): resizable = flag
        }
        let frame: CGRect
        switch rect(element) {
        case .stalled: return .stalled
        case .missing: return .skip
        case .value(let value): frame = value
        }
        return .window(TemplateObservedWindow(pid: app.pid, bundleID: app.bundleID, appName: app.name, title: title,
                                              document: document, frame: frame, minimized: minimized, fullscreen: fullscreen,
                                              resizable: resizable, windowID: id, launchDate: app.launchDate))
    }

    private static func documentURL(_ raw: String) -> String? {
        guard let url = URL(string: raw), ["file", "https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }

    private enum Read<T> {
        case value(T)
        case missing
        case stalled
    }

    private static func fetch(_ element: AXUIElement, _ attribute: String) -> Read<CFTypeRef> {
        var raw: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) {
        case .success:
            guard let raw else { return .missing }
            return .value(raw)
        case .cannotComplete:
            return .stalled
        default:
            return .missing
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> Read<String> {
        switch fetch(element, attribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw):
            guard let text = raw as? String else { return .missing }
            return .value(text)
        }
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Read<Bool> {
        switch fetch(element, attribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw):
            guard let number = raw as? NSNumber else { return .missing }
            return .value(number.boolValue)
        }
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> Read<[AXUIElement]> {
        switch fetch(element, attribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw):
            guard let list = raw as? [AXUIElement] else { return .stalled }
            return .value(list)
        }
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> Read<AXUIElement> {
        switch fetch(element, attribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw):
            guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return .missing }
            return .value(raw as! AXUIElement)
        }
    }

    private static func settable(_ element: AXUIElement, _ attribute: String) -> Read<Bool> {
        var value = DarwinBoolean(false)
        switch AXUIElementIsAttributeSettable(element, attribute as CFString, &value) {
        case .success: return .value(value.boolValue)
        case .cannotComplete: return .stalled
        default: return .missing
        }
    }

    private static func rect(_ element: AXUIElement) -> Read<CGRect> {
        let origin = point(element, kAXPositionAttribute)
        let extent = size(element, kAXSizeAttribute)
        if case .stalled = origin { return .stalled }
        if case .stalled = extent { return .stalled }
        guard case .value(let position) = origin, case .value(let dimensions) = extent,
              [position.x, position.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite) else { return .missing }
        return .value(CGRect(origin: position, size: dimensions))
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> Read<CGPoint> {
        switch fetch(element, attribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw):
            guard CFGetTypeID(raw) == AXValueGetTypeID() else { return .missing }
            var point = CGPoint.zero
            return AXValueGetValue(raw as! AXValue, .cgPoint, &point) ? .value(point) : .missing
        }
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> Read<CGSize> {
        switch fetch(element, attribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let raw):
            guard CFGetTypeID(raw) == AXValueGetTypeID() else { return .missing }
            var size = CGSize.zero
            return AXValueGetValue(raw as! AXValue, .cgSize, &size) ? .value(size) : .missing
        }
    }
}
