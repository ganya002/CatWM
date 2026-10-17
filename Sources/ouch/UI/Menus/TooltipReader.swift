import AppKit
import SwiftUI

struct TooltipReader: NSViewRepresentable {
    let text: String
    let chords: [[String]]

    func makeNSView(context: Context) -> TooltipTrackingView { TooltipTrackingView() }
    func updateNSView(_ v: TooltipTrackingView, context: Context) {
        v.text = text
        v.chords = chords
    }
    static func dismantleNSView(_ v: TooltipTrackingView, coordinator: ()) { Tooltip.shared.leave(v) }
}
