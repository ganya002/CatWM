import AppKit

struct TemplateWindowCandidate: Equatable {
    var windowID: CGWindowID
    var bundleID: String
    var title: String
    var document: String?
    var launchDate: Date?
    var allowsGenericFallback: Bool
    var newlyOpened = false
}

struct TemplateWindowMatch {
    var window: Window
    var bundleID: String
    var title: String
    var document: String?
    var launchDate: Date?
    var allowsGenericFallback: Bool

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

    static func allowsGenericFallback(offSpace: Bool, hiddenWorkspace: Bool) -> Bool {
        !offSpace && !hiddenWorkspace
    }

    static func assign(_ saved: [WorkspaceTemplate.SavedWindow], candidates: [TemplateWindowCandidate]) -> [UUID: CGWindowID] {
        let ordered = candidates.sorted { $0.windowID < $1.windowID }
        var used = Set<CGWindowID>()
        var result: [UUID: CGWindowID] = [:]
        for score in stride(from: 3, through: 0, by: -1) {
            for window in saved where result[window.id] == nil {
                guard let candidate = ordered.first(where: { candidate in
                    guard !used.contains(candidate.windowID), candidate.bundleID == window.bundleID else { return false }
                    guard Self.score(window, title: candidate.title, document: candidate.document,
                                     windowID: candidate.windowID, launchDate: candidate.launchDate) == score else { return false }
                    if score == 0 {
                        guard candidate.allowsGenericFallback else { return false }
                        if !candidate.newlyOpened, !candidate.title.isEmpty, candidate.title != window.title { return false }
                    }
                    return true
                }) else { continue }
                result[window.id] = candidate.windowID
                used.insert(candidate.windowID)
            }
        }
        return result
    }

    static func retainUnscanned(_ previous: [UUID: CGWindowID], assigned: [UUID: CGWindowID],
                                scanned: Set<CGWindowID>, invalidated: Set<CGWindowID> = []) -> [UUID: CGWindowID] {
        var next = assigned
        for (savedID, windowID) in previous where next[savedID] == nil && !scanned.contains(windowID) && !invalidated.contains(windowID) {
            next[savedID] = windowID
        }
        return next
    }

}
