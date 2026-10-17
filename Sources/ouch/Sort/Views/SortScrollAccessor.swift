import AppKit
import SwiftUI

struct SortScrollAccessor: NSViewRepresentable {
    let model: SortModel

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v, weak model] in model?.attach(v?.enclosingScrollView) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { [weak v, weak model] in
            model?.attach(v?.enclosingScrollView)
            model?.measureRow()
        }
    }
}
