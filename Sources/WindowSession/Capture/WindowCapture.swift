import AppKit
import ApplicationServices

public struct AppSnapshot: Sendable {
    public var pid: pid_t
    public var bundleID: String
    public var name: String
    public var launchDate: Date?

    public init(pid: pid_t, bundleID: String, name: String, launchDate: Date?) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.launchDate = launchDate
    }
}

public struct ObservedWindow: Sendable {
    public var pid: pid_t
    public var bundleID: String
    public var appName: String
    public var title: String
    public var document: String?
    public var frame: CGRect
    public var minimized: Bool
    public var fullscreen: Bool
    public var resizable: Bool
    public var windowID: CGWindowID
    public var launchDate: Date?
    public var spaces: [UInt64] = []
    public var floatingOverride = false

    public init(pid: pid_t, bundleID: String, appName: String, title: String, document: String?, frame: CGRect,
                minimized: Bool, fullscreen: Bool, resizable: Bool, windowID: CGWindowID, launchDate: Date?,
                spaces: [UInt64] = [], floatingOverride: Bool = false) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.document = document
        self.frame = frame
        self.minimized = minimized
        self.fullscreen = fullscreen
        self.resizable = resizable
        self.windowID = windowID
        self.launchDate = launchDate
        self.spaces = spaces
        self.floatingOverride = floatingOverride
    }
}

public struct WindowBatch: Sendable {
    public var windows: [ObservedWindow]
    public var focusedID: CGWindowID?
    public var complete: Bool

    public init(windows: [ObservedWindow], focusedID: CGWindowID?, complete: Bool) {
        self.windows = windows
        self.focusedID = focusedID
        self.complete = complete
    }
}

public enum AppRead: Sendable {
    case windows([ObservedWindow])
    case stalled
}

public enum WindowKind {
    public static func includes(subrole: String?, minimized: Bool) -> Bool {
        subrole == kAXStandardWindowSubrole || (minimized && subrole == kAXDialogSubrole)
    }
}

public enum DocumentURL {
    public static func normalized(_ raw: String) -> String? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return nil }
        if ["file", "https", "http"].contains(scheme) { return url.absoluteString }
        return NSWorkspace.shared.urlForApplication(toOpen: url) == nil ? nil : url.absoluteString
    }
}

public enum WindowWalk {
    public static func collect(apps: [AppSnapshot], budget: TimeInterval,
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

public enum WindowCapture {
    public static func collect(apps: [AppSnapshot], frontmostPID: pid_t?, budget: TimeInterval,
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
