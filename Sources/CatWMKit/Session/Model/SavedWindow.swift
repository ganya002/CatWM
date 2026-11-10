import CoreGraphics
import Foundation

package struct SavedWindow: Codable, Identifiable, Equatable, Sendable {
    package var id = UUID()
    package var bundleID: String
    package var appName: String
    package var title: String
    package var document: String?
    package var display: String
    package var frame: CGRect
    package var floating: Bool
    package var minimized: Bool
    package var fullscreen: Bool
    package var zoomed: Bool
    package var focused: Bool
    package var windowID: CGWindowID
    package var launchDate: Date?
    package var state: AppState?
    package var launch: LaunchSpec?

    package init(id: UUID = UUID(), bundleID: String, appName: String, title: String, document: String?,
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

package struct AppState: Codable, Equatable, Sendable {
    package var tabs: [String]
    package var selected: Int

    package init(tabs: [String], selected: Int = 0) {
        self.tabs = tabs
        self.selected = tabs.indices.contains(selected) ? selected : 0
    }

    package var current: String? { tabs.indices.contains(selected) ? tabs[selected] : tabs.first }

    package func kept(_ keep: (String) -> Bool) -> (tabs: [String], selected: Int) {
        let indices = tabs.indices.filter { keep(tabs[$0]) }
        let target = tabs.indices.contains(selected) ? selected : 0
        return (indices.map { tabs[$0] }, indices.firstIndex(of: target) ?? 0)
    }
}

package struct LaunchSpec: Codable, Equatable, Sendable {
    package var url: String?
    package var arguments: [String]?
    package var command: String?

    package init(url: String? = nil, arguments: [String]? = nil, command: String? = nil) {
        self.url = url
        self.arguments = arguments
        self.command = command
    }
}
