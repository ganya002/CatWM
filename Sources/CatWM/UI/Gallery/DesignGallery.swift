#if DEBUG

import AppKit
import CatWMKit
import SwiftUI

final class DesignGallery: NSObject {
    static let shared = DesignGallery()
    private var window: NSWindow?

    func open() {
        if window == nil {
            let gallery = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 780),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
            gallery.title = "CatWM Design Gallery"
            gallery.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: DesignGalleryView { [weak gallery] appearance in
                gallery?.appearance = appearance
            })
            host.sizingOptions = []
            gallery.contentViewController = host
            gallery.setContentSize(NSSize(width: 920, height: 780))
            gallery.contentMinSize = NSSize(width: 640, height: 480)
            gallery.center()
            window = gallery
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

#endif
