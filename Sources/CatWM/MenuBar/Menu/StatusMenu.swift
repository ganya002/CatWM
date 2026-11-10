import AppKit
import CatWMKit
import SwiftUI

final class StatusMenu: NSObject, NSWindowDelegate {
    static let shared = StatusMenu()

    weak var button: NSStatusBarButton?
    let model = MenuModel()
    private var panel: CatWMPanel?
    private let dismiss = DismissMonitor()
    private static var margin: CGFloat { Elevation.popover.room }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard let button, let buttonWindow = button.window, !isOpen else { return }
        guard let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        model.reset()
        model.rebuild()
        model.close = { [weak self] in self?.close() }

        let anchor = buttonWindow.frame, visible = screen.visibleFrame, margin = Self.margin
        let subs = 2 * (Theme.submenuWidth + 48)
        let left = min(max(anchor.minX, visible.minX + 8), visible.maxX - Theme.menuWidth - 8)
        model.opensLeft = left + Theme.menuWidth + subs > visible.maxX - 8
        let width = Theme.menuWidth + subs + 2 * margin
        let x = model.opensLeft ? left - subs - margin : left - margin
        let top = anchor.minY - 4 + margin
        let height = min(top - visible.minY, 820)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        let rootX = model.opensLeft ? subs + margin : margin

        let menuPanel = panel ?? makePanel()
        panel = menuPanel
        menuPanel.contentView = CatWMHostingView(rootView: MenuRoot(model: model, rootX: rootX, top: margin,
                                                                 size: frame.size))
        menuPanel.setFrame(frame, display: true)
        menuPanel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        DispatchQueue.main.async { withAnimation(Motion.easeOut) { self.model.appeared = true } }
        installMonitors()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        dismiss.stop()
        button?.highlight(false)
        Motion.fade(panel, to: 0, duration: 0.12) { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.contentView = nil
            self?.model.reset()
        }
    }

    func refreshIfOpen() { if isOpen { model.refresh() } }

    private func makePanel() -> CatWMPanel {
        let menuPanel = CatWMPanel(role: .menu)
        menuPanel.onClose = { [weak self] in self?.close() }
        menuPanel.delegate = self
        return menuPanel
    }

    func windowDidResignKey(_: Notification) { close() }

    private func installMonitors() {
        dismiss.start(keeps: { [weak self] window in window === self?.panel || window === self?.button?.window },
                      key: { [weak self] event in
                          guard let self, panel?.isKeyWindow == true else { return false }
                          return key(event)
                      },
                      close: { [weak self] in self?.close() })
    }

    private func key(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch (event.keyCode, cmd) {
        case (126, _): model.move(-1)
        case (125, _): model.move(1)
        case (124, false) where model.query.isEmpty: model.openHighlighted()
        case (123, false) where model.query.isEmpty: _ = model.back()
        case (36, _), (76, _): model.runHighlighted()
        case (53, _):
            if !model.query.isEmpty { model.query = "" } else if !model.back() { close() }
        case (43, true): close(); SettingsWindow.shared.show(pane: nil)
        case (44, true): close(); SettingsWindow.shared.show(pane: .shortcuts, map: true)
        case (12, true): NSApp.terminate(nil)
        default: return false
        }
        return true
    }
}
