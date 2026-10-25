import AppKit
import ApplicationServices

struct AppSnapshot: Sendable {
    var pid: pid_t
    var bundleID: String
    var name: String
    var launchDate: Date?
}

struct ObservedWindow: Sendable {
    var pid: pid_t
    var bundleID: String
    var appName: String
    var title: String
    var document: String?
    var frame: CGRect
    var minimized: Bool
    var fullscreen: Bool
    var resizable: Bool
    var windowID: CGWindowID
    var launchDate: Date?
    var spaces: [UInt64] = []
    var floatingOverride = false
}

struct WindowBatch: Sendable {
    var windows: [ObservedWindow]
    var focusedID: CGWindowID?
    var complete: Bool
}

enum AppRead: Sendable {
    case windows([ObservedWindow])
    case stalled
}

enum WindowKind {
    static func includes(subrole: String?, minimized: Bool) -> Bool {
        subrole == kAXStandardWindowSubrole || (minimized && subrole == kAXDialogSubrole)
    }
}

enum DocumentURL {
    static func normalized(_ raw: String) -> String? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return nil }
        if ["file", "https", "http"].contains(scheme) { return url.absoluteString }
        return NSWorkspace.shared.urlForApplication(toOpen: url) == nil ? nil : url.absoluteString
    }
}

enum WindowWalk {
    static func collect(apps: [AppSnapshot], budget: TimeInterval,
                        now: @escaping @Sendable () -> Date = { Date() },
                        stop: @escaping @Sendable () -> Bool = { false },
                        read: (AppSnapshot) -> AppRead) -> WindowBatch {
        let deadline = now().addingTimeInterval(budget)
        func expired() -> Bool { stop() || now() >= deadline }
        var windows: [ObservedWindow] = []
        var complete = !expired()
        if complete {
            for app in apps {
                if expired() {
                    complete = false
                    break
                }
                switch read(app) {
                case .stalled:
                    complete = false
                case .windows(let found):
                    for window in found {
                        if expired() {
                            complete = false
                            break
                        }
                        windows.append(window)
                    }
                }
                if !complete { break }
            }
        }
        return WindowBatch(windows: windows, focusedID: nil, complete: complete)
    }
}

enum WindowCapture {
    static func collect(apps: [AppSnapshot], frontmostPID: pid_t?, budget: TimeInterval,
                        stop: @escaping @Sendable () -> Bool) -> WindowBatch {
        let deadline = Date().addingTimeInterval(budget)
        let expired: @Sendable () -> Bool = { stop() || Date() >= deadline }
        var batch = WindowWalk.collect(apps: apps, budget: budget, stop: expired) { app in
            read(app, expired: expired)
        }
        if batch.complete, let frontmostPID, !expired() {
            batch.focusedID = focusedID(frontmostPID)
        }
        return batch
    }

    private static func read(_ app: AppSnapshot, expired: () -> Bool) -> AppRead {
        if expired() { return .stalled }
        let listed: [AXUIElement]
        switch axApplication(app.pid).readElements(kAXWindowsAttribute) {
        case .stalled: return .stalled
        case .missing: return .windows([])
        case .value(let found): listed = found
        }
        var windows: [ObservedWindow] = []
        for element in listed {
            if expired() { return .stalled }
            AXUIElementSetMessagingTimeout(element, axTimeout)
            switch observe(element, app) {
            case .stalled: return .stalled
            case .missing: continue
            case .value(let window): windows.append(window)
            }
        }
        return .windows(windows)
    }

    private static func focusedID(_ pid: pid_t) -> CGWindowID? {
        guard let focused = axApplication(pid).readElement(kAXFocusedWindowAttribute).value else { return nil }
        AXUIElementSetMessagingTimeout(focused, axTimeout)
        return focused.windowNumber
    }

    private static func observe(_ element: AXUIElement, _ app: AppSnapshot) -> AXRead<ObservedWindow> {
        let subrole: String
        switch element.readString(kAXSubroleAttribute) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let value): subrole = value
        }
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
              let id = element.windowNumber else { return .missing }
        guard case .value(let minimized) = flag(element, kAXMinimizedAttribute) else { return .stalled }
        guard WindowKind.includes(subrole: subrole, minimized: minimized) else { return .missing }
        guard case .value(let fullscreen) = flag(element, "AXFullScreen") else { return .stalled }
        let title: String
        switch element.readString(kAXTitleAttribute) {
        case .stalled: return .stalled
        case .missing: title = ""
        case .value(let text): title = text
        }
        let document: String?
        switch element.readString(kAXDocumentAttribute) {
        case .stalled: return .stalled
        case .missing: document = nil
        case .value(let raw): document = DocumentURL.normalized(raw)
        }
        let resizable: Bool
        switch element.readSettable(kAXSizeAttribute) {
        case .stalled: return .stalled
        case .missing: resizable = false
        case .value(let flag): resizable = flag
        }
        let frame: CGRect
        switch element.readFrame() {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let value): frame = value
        }
        return .value(ObservedWindow(pid: app.pid, bundleID: app.bundleID, appName: app.name, title: title,
                                     document: document, frame: frame, minimized: minimized, fullscreen: fullscreen,
                                     resizable: resizable, windowID: id, launchDate: app.launchDate))
    }

    private static func flag(_ element: AXUIElement, _ attribute: String) -> AXRead<Bool> {
        switch element.readBool(attribute) {
        case .missing: return .value(false)
        case let read: return read
        }
    }
}
