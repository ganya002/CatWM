import AppKit
import SwiftUI

struct SortScrollAccessor: NSViewRepresentable {
    let model: SortModel

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view, weak model] in model?.attach(view?.enclosingScrollView) }
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        DispatchQueue.main.async { [weak view, weak model] in
            model?.attach(view?.enclosingScrollView)
            model?.measureRow()
        }
    }
}
