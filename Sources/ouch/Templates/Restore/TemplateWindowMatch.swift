import AppKit

struct TemplateWindowMatch {
    var window: Window
    var title: String
    var document: String?
    var launchDate: Date?

    static func document(_ element: AXUIElement) -> String? {
        guard let raw = element.string(kAXDocumentAttribute), let url = URL(string: raw),
              ["file", "https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }

    static func score(_ saved: WorkspaceTemplate.SavedWindow, title: String, document: String?,
                      windowID: CGWindowID, launchDate: Date?) -> Int? {
        if let expected = saved.document, expected != document {
            guard document == nil, !saved.title.isEmpty, saved.title == title else { return nil }
        }
        if saved.windowID == windowID, let date = saved.launchDate, date == launchDate { return 3 }
        if saved.document != nil, saved.document == document { return 2 }
        if !saved.title.isEmpty, saved.title == title { return 1 }
        return saved.document == nil ? 0 : nil
    }

    static func read(bundleID: String, manager: WindowManager) -> [TemplateWindowMatch] {
        let screens = Screen.all()
        let spaces = Set(screens.map { Spaces.current(display: $0.uuid) })
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap { app in
            axApp(app.processIdentifier).elements(kAXWindowsAttribute).compactMap { element in
                guard element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole, let id = element.windowID else { return nil }
                let ownSpaces = Spaces.of(window: id)
                let fullscreen = element.bool("AXFullScreen") == true
                if !fullscreen, !ownSpaces.isEmpty && spaces.isDisjoint(with: ownSpaces) { return nil }
                if !fullscreen, let ws = manager.workspaceOf[id], !manager.isShown(ws) { return nil }
                let window = manager.windows[id] ?? Window(id: id, element: element, pid: app.processIdentifier, bundleID: bundleID)
                return TemplateWindowMatch(window: window, title: element.string(kAXTitleAttribute) ?? "",
                                           document: document(element), launchDate: app.launchDate)
            }
        }.sorted { $0.window.id < $1.window.id }
    }
}
