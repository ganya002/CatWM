import AppKit
import SwiftUI

final class StatusMenu: NSObject, NSWindowDelegate {
    static let shared = StatusMenu()

    weak var button: NSStatusBarButton?
    let model = MenuModel()
    private var panel: OuchPanel?
    private let dismiss = DismissMonitor()
    private static let margin: CGFloat = 26

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard let button, let bw = button.window, !isOpen else { return }
        let screen = bw.screen ?? NSScreen.main ?? NSScreen.screens[0]
        model.reset()
        model.rebuild()
        model.close = { [weak self] in self?.close() }

        let b = bw.frame, v = screen.visibleFrame, m = Self.margin
        let subs = 2 * (Theme.submenuWidth + 48)
        let left = min(max(b.minX, v.minX + 8), v.maxX - Theme.menuWidth - 8)
        model.opensLeft = left + Theme.menuWidth + subs > v.maxX - 8
        let width = Theme.menuWidth + subs + 2 * m
        let x = model.opensLeft ? left - subs - m : left - m
        let top = b.minY - 4 + m / 4
        let height = min(top - v.minY, 820)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        let rootX = model.opensLeft ? subs + m : m

        let p = panel ?? makePanel()
        panel = p
        p.contentView = OuchHostingView(rootView: MenuRoot(model: model, rootX: rootX, top: m / 4,
                                                         size: frame.size))
        p.setFrame(frame, display: true)
        p.makeKeyAndOrderFront(nil)
        button.highlight(true)
        DispatchQueue.main.async { withAnimation(Motion.easeOut) { self.model.appeared = true } }
        installMonitors()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        dismiss.stop()
        button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.contentView = nil
            self?.model.reset()
        })
    }

    func refreshIfOpen() { if isOpen { model.refresh() } }

    private func makePanel() -> OuchPanel {
        let p = OuchPanel(role: .menu)
        p.onClose = { [weak self] in self?.close() }
        p.delegate = self
        return p
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func installMonitors() {
        dismiss.start(keeps: { [weak self] w in w === self?.panel || w === self?.button?.window },
                      key: { [weak self] e in
                          guard let self, panel?.isKeyWindow == true else { return false }
                          return key(e)
                      },
                      close: { [weak self] in self?.close() })
    }

    private func key(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd) {
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
