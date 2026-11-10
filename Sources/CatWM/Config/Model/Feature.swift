import Foundation

enum Feature: String, CaseIterable {
    case tiling, tabGroups, desktops
    case keys, mouse, gestures, cursorActions
    case notifications, sessions, templates, socket
    case tabStrips, hud, dimming, switcher, overview, keyHelp

    enum Group: String, CaseIterable {
        case windows, input, services, presentation
    }

    var group: Group {
        switch self {
        case .tiling, .tabGroups, .desktops: .windows
        case .keys, .mouse, .gestures, .cursorActions: .input
        case .notifications, .sessions, .templates, .socket: .services
        case .tabStrips, .hud, .dimming, .switcher, .overview, .keyHelp: .presentation
        }
    }

    var summary: String {
        switch self {
        case .tiling: "Lay out windows with the layouts"
        case .tabGroups: "Group windows as tabs"
        case .desktops: "Run each workspace as a macOS Desktop"
        case .keys: "Read key presses for the binds"
        case .mouse: "Swap and resize windows with the mouse, and pull windows from the Dock"
        case .gestures: "Switch workspaces with trackpad swipes"
        case .cursorActions: "Quick actions at the pointer in window mode"
        case .notifications: "Unread badges on tabs"
        case .sessions: "Save and open app windows, tabs and folders"
        case .templates: "Saved workspace templates"
        case .socket: "The control socket for the CLI and the libraries"
        case .tabStrips: "The tab strip above a tab group"
        case .hud: "The layout and config messages"
        case .dimming: "Dim and blur the other windows"
        case .switcher: "The window switcher"
        case .overview: "The Overview of every workspace"
        case .keyHelp: "The keyboard help in window mode"
        }
    }

    var needs: [Feature] {
        switch self {
        case .tabStrips: [.tabGroups]
        case .keyHelp, .cursorActions: [.keys]
        case .templates: [.sessions]
        default: []
        }
    }

    var path: String { "features.\(group.rawValue).\(rawValue)" }
}
