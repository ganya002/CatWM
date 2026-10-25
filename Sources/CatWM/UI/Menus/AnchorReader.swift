import AppKit
import SwiftUI

struct AnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor
    func makeNSView(context _: Context) -> NSView {
        let view = PassThroughView()
        anchor.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context _: Context) { anchor.view = nsView }
}
