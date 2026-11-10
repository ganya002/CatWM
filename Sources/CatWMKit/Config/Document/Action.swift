import Foundation

package struct Action: Identifiable {
    package let title: String
    package let category: ActionCategory
    package let dispatcher: String
    package let args: String
    package let symbol: String
    package var group: String?
    package var short: String?
    package var focusRequired: FocusRequirement = .byCategory
    package var requiresFocus: Bool {
        switch focusRequired {
        case .byCategory: [.focus, .move, .layout, .window, .custom].contains(category)
        case .required: true
        case .notRequired: false
        }
    }
    package var id: String { "\(dispatcher) \(args)" }

    package init(title: String, category: ActionCategory, dispatcher: String, args: String, symbol: String,
                 group: String? = nil, short: String? = nil, focusRequired: FocusRequirement = .byCategory) {
        self.title = title
        self.category = category
        self.dispatcher = dispatcher
        self.args = args
        self.symbol = symbol
        self.group = group
        self.short = short
        self.focusRequired = focusRequired
    }
}

package enum FocusRequirement: ExpressibleByBooleanLiteral {
    case byCategory, required, notRequired

    package init(booleanLiteral value: Bool) { self = value ? .required : .notRequired }
}

package enum ActionCategory: String, CaseIterable, Identifiable {
    case focus = "Focus", move = "Move Windows", layout = "Layout", window = "Window", displays = "Displays"
    case spaces = "Workspaces", commands = "Commands", app = "CatWM", custom = "Custom"
    package var id: Self { self }
    package var symbol: String {
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
