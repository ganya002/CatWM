import AppKit
import SwiftUI

extension Layout {
    var blurb: String {
        switch self {
        case .tall: "Main left, the rest stacked right"
        case .tallRight: "Main right, the rest stacked left"
        case .wide: "Main on top, the rest below"
        case .middleWide: "Main in the middle, the rest beside"
        case .fullscreen: "Every window fills the screen"
        case .column: "Equal-width columns"
        case .row: "Equal-height rows"
        case .floating: "Windows stay where you put them"
        case .bsp: "Each window halves the last one"
        case .threeColumnLeft: "Main left, two columns right"
        case .threeColumnMiddle: "Main in the middle column"
        case .threeColumnRight: "Main right, two columns left"
        case .twoPane: "Main left, one window right"
        case .twoPaneRight: "Main right, one window left"
        case .widescreenTall: "Mains side by side, the rest right"
        case .widescreenTallRight: "Mains side by side, the rest left"
        }
    }
}
