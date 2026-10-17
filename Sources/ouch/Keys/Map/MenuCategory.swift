import AppKit
import SwiftUI

enum MenuCategory: String, CaseIterable, Identifiable {
    case focus = "Focus", move = "Move", workspace = "Workspace", layout = "Layout", window = "Window", mode = "Mode", app = "App"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .focus: "scope"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .workspace: "square.stack.3d.up"
        case .layout: "rectangle.split.3x1"
        case .window: "macwindow"
        case .mode: "keyboard"
        case .app: "gearshape"
        }
    }

    init(_ a: Action) {
        switch a.category {
        case .focus: self = .focus
        case .move: self = .move
        case .displays: self = a.dispatcher == "focusmonitor" ? .focus : .move
        case .spaces: self = .workspace
        case .layout: self = .layout
        case .window, .commands: self = .window
        case .app, .custom: self = a.dispatcher == "submap" ? .mode : .app
        }
    }
}
