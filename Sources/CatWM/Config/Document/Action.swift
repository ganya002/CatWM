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
        case .byCategory: [.focus, .move, .layout, .window, .custom].contains(category)
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
