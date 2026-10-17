import AppKit

extension Layout {
    var hasMainPane: Bool {
        switch self {
        case .fullscreen, .column, .row, .floating: false
        default: true
        }
    }
}
