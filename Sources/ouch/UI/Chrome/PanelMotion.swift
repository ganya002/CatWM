import AppKit
import SwiftUI

enum PanelMotion: String, CaseIterable {
    case rise
    case pop
    case focus
    case tile
    case draw

    static var current: PanelMotion { preview ?? WindowManager.shared.config.panelAnimation }
    static var preview: PanelMotion?

    var title: String {
        switch self {
        case .rise: "Rise"
        case .pop: "Pop"
        case .focus: "Focus"
        case .tile: "Tile"
        case .draw: "Draw"
        }
    }

    var outDuration: Double { self == .focus ? 0.22 : self == .pop ? 0.2 : 0.18 }

    func animation(in shown: Bool) -> Animation {
        guard shown else {
            return self == .focus ? .easeIn(duration: outDuration) : .timingCurve(0.4, 0, 1, 1, duration: outDuration)
        }
        switch self {
        case .rise: return .spring(response: 0.38, dampingFraction: 0.86)
        case .pop: return .spring(response: 0.42, dampingFraction: 0.58)
        case .focus: return .timingCurve(0.16, 1, 0.3, 1, duration: 0.42)
        case .tile: return .linear(duration: Self.tileDuration)
        case .draw: return .linear(duration: 0.45)
        }
    }

    static var tileDuration: Double { max(0.3, WindowManager.shared.config.animationDuration * 1.7) }
}
