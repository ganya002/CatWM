import AppKit
import SwiftUI

final class IntroLab {
    static let shared = IntroLab()
    private var window: NSPanel?
    private let model = IntroLabModel()

    func open() {
        if window == nil {
            let rect = NSRect(x: 0, y: 0, width: 520, height: 640)
            let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            let panel = NSPanel( // style-ok: debug intro lab window
                contentRect: rect, styleMask: style, backing: .buffered, defer: false)
            panel.title = "Intro Lab"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: IntroLabView(model: model))
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
