import CoreGraphics
import Foundation

public struct SavedWindow: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var bundleID: String
    public var appName: String
    public var title: String
    public var document: String?
    public var display: String
    public var frame: CGRect
    public var floating: Bool
    public var minimized: Bool
    public var fullscreen: Bool
    public var zoomed: Bool
    public var focused: Bool
    public var windowID: CGWindowID
    public var launchDate: Date?
    public var state: AppState?
    public var launch: LaunchSpec?

    public init(id: UUID = UUID(), bundleID: String, appName: String, title: String, document: String?,
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

public struct AppState: Codable, Equatable, Sendable {
    public var tabs: [String]
    public var selected: Int

    public init(tabs: [String], selected: Int = 0) {
        self.tabs = tabs
        self.selected = tabs.indices.contains(selected) ? selected : 0
    }

    public var current: String? { tabs.indices.contains(selected) ? tabs[selected] : tabs.first }

    func kept(_ keep: (String) -> Bool) -> (tabs: [String], selected: Int) {
        let indices = tabs.indices.filter { keep(tabs[$0]) }
        let target = tabs.indices.contains(selected) ? selected : 0
        return (indices.map { tabs[$0] }, indices.firstIndex(of: target) ?? 0)
    }
}

public struct LaunchSpec: Codable, Equatable, Sendable {
    public var url: String?
    public var arguments: [String]?
    public var command: String?

    public init(url: String? = nil, arguments: [String]? = nil, command: String? = nil) {
        self.url = url
        self.arguments = arguments
        self.command = command
    }
}
