import CoreGraphics
import Foundation

struct SavedWindow: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String
    var document: String?
    var display: String
    var frame: CGRect
    var floating: Bool
    var minimized: Bool
    var fullscreen: Bool
    var zoomed: Bool
    var focused: Bool
    var windowID: CGWindowID
    var launchDate: Date?
    var state: AppState?
    var launch: LaunchSpec?

    init(id: UUID = UUID(), bundleID: String, appName: String, title: String, document: String?,
         display: String, frame: CGRect, floating: Bool, minimized: Bool, fullscreen: Bool, zoomed: Bool,
         focused: Bool, windowID: CGWindowID, launchDate: Date?, state: AppState? = nil,
         launch: LaunchSpec? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.document = document
        self.display = display
        self.frame = frame
        self.floating = floating
        self.minimized = minimized
        self.fullscreen = fullscreen
        self.zoomed = zoomed
        self.focused = focused
        self.windowID = windowID
        self.launchDate = launchDate
        self.state = state
        self.launch = launch
    }
}

struct AppState: Codable, Equatable, Sendable {
    var tabs: [String]
    var selected: Int

    init(tabs: [String], selected: Int = 0) {
        self.tabs = tabs
        self.selected = tabs.indices.contains(selected) ? selected : 0
    }

    var current: String? { tabs.indices.contains(selected) ? tabs[selected] : tabs.first }

    func kept(_ keep: (String) -> Bool) -> (tabs: [String], selected: Int) {
        let indices = tabs.indices.filter { keep(tabs[$0]) }
        let target = tabs.indices.contains(selected) ? selected : 0
        return (indices.map { tabs[$0] }, indices.firstIndex(of: target) ?? 0)
    }
}

struct LaunchSpec: Codable, Equatable, Sendable {
    var url: String?
    var arguments: [String]?
    var command: String?

    init(url: String? = nil, arguments: [String]? = nil, command: String? = nil) {
        self.url = url
        self.arguments = arguments
        self.command = command
    }
}
