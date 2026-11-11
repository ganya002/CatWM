import AppKit
import CatWMKit
import SwiftUI

@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?
    private var sessionOpen = false
    let doc = ConfigDocument()
    private(set) lazy var library = ConfigLibrary(doc: doc)
    private(set) lazy var settingsUI = SettingsUI(doc: doc)

    func show(pane: Pane?, map: Bool = false) {
        guard !Instance.isContained else { return }
        let wasVisible = sessionOpen
        if window == nil {
            let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                                          styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                                      .fullSizeContentView],
                                          backing: .buffered, defer: false)
            settingsWindow.title = "CatWM Settings"
            settingsWindow.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: SettingsView(doc: doc, settingsUI: settingsUI))
            host.sizingOptions = []
            settingsWindow.contentViewController = host
            ArrowCursor.keep(in: host.view)
            settingsWindow.setContentSize(NSSize(width: 880, height: 620))
            settingsWindow.contentMinSize = NSSize(width: 760, height: 520)
            settingsWindow.clearTitlebar(hiding: [.zoomButton])
            settingsWindow.collectionBehavior.insert(.fullScreenNone)
            settingsWindow.delegate = self
            window = settingsWindow
        }
        if let pane {
            settingsUI.pane = pane
            settingsUI.showMap = false
            settingsUI.search = ""
        }
        if map { settingsUI.showMap = true }
        if !wasVisible {
            sessionOpen = true
            doc.beginSession()
            settingsUI.beginSession()
            centerOnPointerScreen()
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !wasVisible { DispatchQueue.main.async { self.window?.makeFirstResponder(nil) } }
        Tips.shared.paneShown(settingsUI.pane)
    }

    private func centerOnPointerScreen() {
        guard let window, let area = CatWMPanel.pointerScreen()?.visibleFrame else { return }
        let size = NSSize(width: min(window.frame.width, area.width), height: min(window.frame.height, area.height))
        window.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                               width: size.width, height: size.height),
                        display: false)
    }

    func windowDidUpdate(_: Notification) {
        if window?.standardWindowButton(.zoomButton)?.isHidden == false {
            window?.standardWindowButton(.zoomButton)?.isHidden = true
        }
        placeTrafficLights()
    }

    func windowDidResize(_: Notification) { placeTrafficLights() }

    static let titlebarHeight: CGFloat = 48

    private func placeTrafficLights() {
        guard let window, let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let bar = close.superview, let container = bar.superview else { return }
        let height = Self.titlebarHeight
        if container.frame.height != height {
            container.setFrameSize(NSSize(width: container.frame.width, height: height))
            container.setFrameOrigin(NSPoint(x: container.frame.minX,
                                             y: (container.superview?.frame.height ?? window.frame.height) - height))
            bar.setFrameSize(NSSize(width: bar.frame.width, height: height))
        }
        let y = (height - close.frame.height) / 2
        for (i, button) in [close, mini].enumerated() {
            let x = 22 + CGFloat(i) * 20
            if button.frame.origin != NSPoint(x: x, y: y) { button.setFrameOrigin(NSPoint(x: x, y: y)) }
        }
    }

    func windowShouldZoom(_: NSWindow, toFrame _: NSRect) -> Bool { false }

    func windowWillClose(_: Notification) {
        sessionOpen = false
        settingsUI.endSession()
        Tips.shared.settingsClosed()
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor func confirm(_ title: String, _ detail: String, button: String = "Reset") -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.addButton(withTitle: button)
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
}
