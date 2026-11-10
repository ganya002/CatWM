import AppKit
import CatWMKit
import SwiftUI

extension PanelMotion {
    static var current: PanelMotion { PanelMotionDemo.shared.preview ?? WindowManager.shared.config.panelAnimation }

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
