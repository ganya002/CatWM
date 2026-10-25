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

    var outDuration: Double {
        switch self {
        case .rise, .pop, .focus: Self.windowDuration
        default: 0.18
        }
    }

    func animation(in shown: Bool) -> Animation? {
        switch self {
        case .rise, .pop, .focus:
            return Self.windowAnimation
        case .tile:
            return shown ? .linear(duration: Self.tileDuration) : exitAnimation
        case .draw:
            return shown ? .linear(duration: 0.45) : exitAnimation
        }
    }

    private var exitAnimation: Animation { .timingCurve(0.4, 0, 1, 1, duration: outDuration) }

    static var windowDuration: Double {
        let config = WindowManager.shared.config
        return config.animate ? config.animationDuration : 0
    }

    static var windowAnimation: Animation? {
        let config = WindowManager.shared.config
        guard config.animate else { return nil }
        return Animation(CurveAnimation(curve: config.animationCurve, bounce: config.animationBounce,
                                        duration: config.animationDuration))
    }

    static var tileDuration: Double { max(0.3, WindowManager.shared.config.animationDuration * 1.7) }
}
