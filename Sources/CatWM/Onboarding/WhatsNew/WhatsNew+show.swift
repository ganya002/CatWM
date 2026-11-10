import AppKit
import CatWMKit
import SwiftUI

extension WhatsNew {
    func show(takeFocus: Bool = true) {
        let news = unseen
        let shown = news.isEmpty
            ? releases.first.map { release in release.features.map { (release.version, $0) } } ?? []
            : news
        guard !shown.isEmpty else { return }
        hide()
        Tips.shared.dismissAll()
        var versions: [String] = []
        for (version, _) in shown where !versions.contains(version) { versions.append(version) }
        model.versions = versions.count > 1 ? "\(versions.last ?? "") – \(versions[0])" : versions[0]
        model.features = shown.map(\.feature)
        model.close = { [weak self] in self?.hide() }
        model.tour = { [weak self] in self?.startTour() }
        model.run = { [weak self] action in
            self?.hide()
            action()
        }
        let host = CatWMHostingView(rootView: WhatsNewView(model: model))
        let panel = CatWMPanel(role: .card(.floating))
        panel.onClose = { [weak self] in self?.hide() }
        panel.contentView = host
        place(panel, host: host)
        panel.alphaValue = 0
        if takeFocus {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        Motion.group(0.35) { Motion.setAlpha(1, on: panel) }
        self.panel = panel
        markSeen(model.features)
        StatusMenu.shared.refreshIfOpen()
    }

    func hide() {
        guard let hidden = panel else { return }
        panel = nil
        Motion.group(0.2, changes: { Motion.setAlpha(0, on: hidden) }, completion: { hidden.orderOut(nil) })
    }

    private func startTour() {
        let features = model.features
        hide()
        Onboarding.shared.run(CatchUpLesson(features: features)) { how in
            if how == .finished { HUD.shared.show("You're caught up", on: nil) }
        }
    }

    private func place(_ panel: CatWMPanel, host: CatWMHostingView<WhatsNewView>) {
        model.caret = nil
        let inset = WhatsNewView.inset
        guard let button = Onboarding.shared.statusButton?.window?.frame else {
            guard let screen = CatWMPanel.pointerScreen() else { return }
            panel.setFrame(CatWMPanel.frame(size: host.fittingSize, on: screen, anchor: .center(dy: -12), inset: inset),
                           display: false)
            return
        }
        guard let screen = CatWMPanel.screen(at: NSPoint(x: button.midX, y: button.midY)) else { return }
        let visible = screen.visibleFrame
        let size = host.fittingSize
        let card = NSSize(width: size.width - inset.leading - inset.trailing,
                          height: size.height - inset.top - inset.bottom)
        let x = min(max(button.midX - card.width + 60, visible.minX + 16), visible.maxX - card.width - 16)
        model.caret = min(max(button.midX - x, 30), card.width - 30)
        let origin = NSPoint(x: x - inset.leading, y: button.minY - 10 - card.height - inset.bottom)
        panel.setFrame(CatWMPanel.frame(size: size, on: screen, anchor: .origin(origin), inset: inset).integral,
                       display: false)
    }
}
