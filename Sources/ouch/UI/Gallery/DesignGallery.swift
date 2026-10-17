#if DEBUG

import AppKit
import SwiftUI

final class DesignGallery: NSObject {
    static let shared = DesignGallery()
    private var window: NSWindow?

    func open() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 780),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Ouch Design Gallery"
            w.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: DesignGalleryView { [weak w] appearance in
                w?.appearance = appearance
            })
            host.sizingOptions = []
            w.contentViewController = host
            w.setContentSize(NSSize(width: 920, height: 780))
            w.contentMinSize = NSSize(width: 640, height: 480)
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

#endif
