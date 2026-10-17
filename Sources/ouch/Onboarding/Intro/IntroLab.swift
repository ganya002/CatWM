import AppKit
import SwiftUI

final class IntroLab {
    static let shared = IntroLab()
    private var window: NSPanel?
    private let model = IntroLabModel()

    func open() {
        if window == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), // style-ok: debug intro lab window
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            p.title = "Intro Lab"
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: IntroLabView(model: model))
            p.center()
            window = p
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
