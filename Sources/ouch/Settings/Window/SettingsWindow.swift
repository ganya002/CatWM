import AppKit
import SwiftUI

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?
    let doc = ConfigDocument()
    private(set) lazy var library = ConfigLibrary(doc: doc)
    private(set) lazy var ui = SettingsUI(doc: doc)

    func show(pane: Pane?, map: Bool = false) {
        let wasVisible = window?.isVisible ?? false
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Ouch Settings"
            w.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: SettingsView(doc: doc, ui: ui))
            host.sizingOptions = []
            w.contentViewController = host
            ArrowCursor.keep(in: host.view)
            w.setContentSize(NSSize(width: 940, height: 680))
            w.contentMinSize = NSSize(width: 840, height: 540)
            w.level = .floating
            w.clearTitlebar(hiding: [.zoomButton])
            w.collectionBehavior.insert(.fullScreenNone)
            w.delegate = self
            window = w
        }
        if let pane {
            ui.pane = pane
            ui.showMap = false
            ui.search = ""
        }
        if map { ui.showMap = true }
        if !wasVisible {
            doc.beginSession()
            ui.beginSession()
            centerOnPointerScreen()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !wasVisible { DispatchQueue.main.async { self.window?.makeFirstResponder(nil) } }
        Tips.shared.paneShown(ui.pane)
    }

    private func centerOnPointerScreen() {
        guard let w = window else { return }
        let area = OuchPanel.pointerScreen().visibleFrame
        let size = NSSize(width: min(w.frame.width, area.width), height: min(w.frame.height, area.height))
        w.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height),
                   display: false)
    }

    func windowDidUpdate(_ notification: Notification) {
        if window?.standardWindowButton(.zoomButton)?.isHidden == false { window?.standardWindowButton(.zoomButton)?.isHidden = true }
        placeTrafficLights()
    }

    func windowDidResize(_ notification: Notification) { placeTrafficLights() }

    static let titlebarHeight: CGFloat = 48

    private func placeTrafficLights() {
        guard let w = window, let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton),
              let bar = close.superview, let container = bar.superview else { return }
        let h = Self.titlebarHeight
        if container.frame.height != h {
            container.setFrameSize(NSSize(width: container.frame.width, height: h))
            container.setFrameOrigin(NSPoint(x: container.frame.minX, y: (container.superview?.frame.height ?? w.frame.height) - h))
            bar.setFrameSize(NSSize(width: bar.frame.width, height: h))
        }
        let y = (h - close.frame.height) / 2
        for (i, b) in [close, mini].enumerated() {
            let x = 22 + CGFloat(i) * 20
            if b.frame.origin != NSPoint(x: x, y: y) { b.setFrameOrigin(NSPoint(x: x, y: y)) }
        }
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        ui.endSession()
        Tips.shared.settingsClosed()
        NSApp.setActivationPolicy(.accessory)
    }
}
