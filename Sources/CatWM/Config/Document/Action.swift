import AppKit
import Carbon
import Combine
import SwiftUI

struct Action: Identifiable {
    let title: String
    let category: ActionCategory
    let dispatcher: String
    let args: String
    let symbol: String
    var group: String?
    var short: String?
    var focusRequired: FocusRequirement = .byCategory
    var requiresFocus: Bool {
        switch focusRequired {
        case .byCategory: [.focus, .move, .columns, .window, .custom].contains(category)
        case .required: true
        case .notRequired: false
        }
    }
    var id: String { "\(dispatcher) \(args)" }
}

enum FocusRequirement: ExpressibleByBooleanLiteral {
    case byCategory, required, notRequired

    init(booleanLiteral value: Bool) { self = value ? .required : .notRequired }
}

enum ActionCategory: String, CaseIterable, Identifiable {
    case focus = "Focus", move = "Move Windows", columns = "Columns", window = "Window", displays = "Displays"
    case spaces = "Workspaces", commands = "Commands", app = "CatWM", custom = "Custom"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .focus: "scope"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .columns: "rectangle.split.3x1"
        case .window: "macwindow"
        case .displays: "display.2"
        case .spaces: "square.stack.3d.up"
        case .commands: "terminal"
        case .app: "gearshape"
        case .custom: "curlybraces"
        }
    }
}
