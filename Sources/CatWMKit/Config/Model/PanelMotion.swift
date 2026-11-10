import Foundation

package enum PanelMotion: String, CaseIterable {
    case rise
    case pop
    case focus
    case tile
    case draw

    package var title: String {
        switch self {
        case .rise: "Rise"
        case .pop: "Pop"
        case .focus: "Focus"
        case .tile: "Tile"
        case .draw: "Draw"
        }
    }
}
