import AppKit
import Carbon
import Combine
import SwiftUI

enum ActionCategory: String, CaseIterable, Identifiable {
    case focus = "Focus", move = "Move Windows", layout = "Layout", window = "Window", displays = "Displays"
    case spaces = "Workspaces", commands = "Commands", app = "CatWM", custom = "Custom"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .focus: "scope"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .layout: "rectangle.split.3x1"
        case .window: "macwindow"
        case .displays: "display.2"
        case .spaces: "square.stack.3d.up"
        case .commands: "terminal"
        case .app: "gearshape"
        case .custom: "curlybraces"
        }
    }
}
