import CatWMKit

extension Pane {
    var configKind: ConfigKind? {
        switch self {
        case .motion: .animation
        case .shortcuts: .keyboard
        default: nil
        }
    }
}
