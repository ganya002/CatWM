import AppKit
import SwiftUI

enum PanelMotion: String, CaseIterable {
    case rise
    case pop
    case focus
    case tile
    case draw

    static var current: PanelMotion { PanelMotionDemo.shared.preview ?? WindowManager.shared.config.panelAnimation }

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
            return Motion.user
        case .tile:
            return shown ? Motion.tile(duration: Self.tileDuration) : exitAnimation
        case .draw:
            return shown ? Motion.draw : exitAnimation
        }
    }

    private var exitAnimation: Animation { Motion.panelExit(duration: outDuration) }

    static var windowDuration: Double {
        let config = WindowManager.shared.config
        return config.animate ? config.animationDuration : 0
    }

    static var tileDuration: Double { max(0.3, WindowManager.shared.config.animationDuration * 1.7) }
}
