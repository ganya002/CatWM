import AppKit

enum SortStrategy: String, CaseIterable {
    case task, app, focus, none

    var title: String {
        switch self {
        case .task: "By task"
        case .app: "By app"
        case .focus: "Focus"
        case .none: "Start empty"
        }
    }
}
