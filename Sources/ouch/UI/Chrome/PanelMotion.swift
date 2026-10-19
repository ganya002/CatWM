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
        case .rise, .pop, .focus: Self.windowAnimation
        case .tile: shown ? .linear(duration: Self.tileDuration) : .timingCurve(0.4, 0, 1, 1, duration: outDuration)
        case .draw: shown ? .linear(duration: 0.45) : .timingCurve(0.4, 0, 1, 1, duration: outDuration)
        }
    }

    static var windowDuration: Double {
        let c = WindowManager.shared.config
        return c.animate ? c.animationDuration : 0
    }

    static var windowAnimation: Animation? {
        let c = WindowManager.shared.config
        guard c.animate else { return nil }
        return Animation(CurveAnimation(curve: c.animationCurve, bounce: c.animationBounce, duration: c.animationDuration))
    }

    static var tileDuration: Double { max(0.3, WindowManager.shared.config.animationDuration * 1.7) }
}
