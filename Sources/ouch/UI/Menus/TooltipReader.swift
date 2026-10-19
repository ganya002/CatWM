import AppKit
import SwiftUI

struct TooltipReader: NSViewRepresentable {
    let text: String
    let chords: [[String]]

    func makeNSView(context _: Context) -> TooltipTrackingView { TooltipTrackingView() }
    func updateNSView(_ view: TooltipTrackingView, context _: Context) {
        view.text = text
        view.chords = chords
    }
    static func dismantleNSView(_ view: TooltipTrackingView, coordinator _: ()) { Tooltip.shared.leave(view) }
}
