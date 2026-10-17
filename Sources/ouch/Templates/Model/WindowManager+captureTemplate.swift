import AppKit

extension WindowManager {
    enum TemplateError: LocalizedError {
        case notReady, empty
        var errorDescription: String? {
            switch self {
            case .notReady: "Grant Accessibility access before you save or open a template."
            case .empty: "Open a window in this workspace before you save a template."
            }
        }
    }

    func captureTemplate() throws -> WorkspaceTemplate {
        guard isStarted else { throw TemplateError.notReady }
        let screens = Screen.all()
        guard !screens.isEmpty else { throw TemplateError.notReady }
        let mainID = NSScreen.screens.first?.displayID
        let displays = screens.map { screen in
            let state = state(for: screen)
            return WorkspaceTemplate.Display(id: screen.uuid, name: screen.ns.localizedName, frame: screen.frame,
                                             visible: screen.visible, isMain: screen.id == mainID,
                                             layout: state.layout.rawValue, ratio: state.ratio, mainCount: state.mainCount)
        }
        let focused = NSWorkspace.shared.frontmostApplication.flatMap {
            axApp($0.processIdentifier).element(kAXFocusedWindowAttribute)?.windowID
        } ?? model.mostRecent(of: visible)
        let currentSpaces = Set(screens.map { Spaces.current(display: $0.uuid) })
        var captured: [WorkspaceTemplate.SavedWindow] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            guard let bundle = app.bundleIdentifier else { continue }
            for element in axApp(app.processIdentifier).elements(kAXWindowsAttribute) {
                guard element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole, let id = element.windowID else { continue }
                let fullscreen = element.bool("AXFullScreen") == true
                if let ws = workspaceOf[id], !isShown(ws), !fullscreen { continue }
                let spaces = Spaces.of(window: id)
                if !spaces.isEmpty && currentSpaces.isDisjoint(with: spaces) { continue }
                let window = windows[id] ?? Window(id: id, element: element, pid: app.processIdentifier, bundleID: bundle)
                if windows[id] == nil { window.autoFloating = shouldFloat(window, title: element.string(kAXTitleAttribute), resizable: element.isSettable(kAXSizeAttribute)) }
                let frame = fullscreen && !window.naturalFrame.isNull ? window.naturalFrame : window.frame
                guard !frame.isNull, !frame.isEmpty, let screen = screen(of: window, in: screens) else { continue }
                let state = state(for: screen)
                captured.append(.init(bundleID: bundle, appName: app.localizedName ?? bundle,
                                      title: element.string(kAXTitleAttribute) ?? "",
                                      document: TemplateWindowMatch.document(element), display: screen.uuid, frame: frame,
                                      floating: window.isFloating, minimized: element.bool(kAXMinimizedAttribute) == true,
                                      fullscreen: window.isNativeFullscreen, zoomed: state.zoomed == id,
                                      focused: focused == id, windowID: id, launchDate: app.launchDate))
            }
        }
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        captured.sort { (positions[$0.windowID] ?? Int.max, $0.windowID) < (positions[$1.windowID] ?? Int.max, $1.windowID) }
        guard !captured.isEmpty else { throw TemplateError.empty }
        return WorkspaceTemplate(name: "", tilingEnabled: tilingEnabled, displays: displays, windows: captured)
    }
}
