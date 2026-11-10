import AppKit
import CatWMKit
import SwiftUI

enum MenuCategory: String, CaseIterable, Identifiable {
    case focus = "Focus", move = "Move", workspace = "Workspace", layout = "Layout", window = "Window", mode = "Mode"
    case app = "App"
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

    init(_ action: Action) {
        switch action.category {
        case .focus: self = .focus
        case .move: self = .move
        case .displays: self = action.dispatcher == WindowActions.focusmonitor.name ? .focus : .move
        case .spaces: self = .workspace
        case .layout: self = .layout
        case .window, .commands: self = .window
        case .app, .custom: self = action.dispatcher == WindowActions.submap.name ? .mode : .app
        }
    }
}

struct CategoryAnchor: PreferenceKey {
    static var defaultValue: [MenuCategory: Anchor<CGRect>] = [:]
    static func reduce(value: inout [MenuCategory: Anchor<CGRect>], nextValue: () -> [MenuCategory: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
