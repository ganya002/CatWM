import AppKit
import SwiftUI

extension PermissionGuide {
    func appear() {
        guard let panel else { return }
        panel.alphaValue = 0
        let frame = desiredFrame()
        placed = frame
        movedAt = Date()
        panel.setFrame(frame.offsetBy(dx: 0, dy: -6), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = Motion.Curve.fade
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    func fadeOut() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.pending == false || self?.hidden == true { panel.orderOut(nil) }
        })
    }

    func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 10),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        p.clearTitlebar(hiding: [.closeButton, .miniaturizeButton, .zoomButton])
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: GuideView(model: model, dismiss: { [weak self] in self?.hide() }))
        host.sizingOptions = [.intrinsicContentSize]
        host.safeAreaRegions = []
        if #available(macOS 26.0, *) {
            p.isOpaque = false
            p.backgroundColor = .clear
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.Radius.xl
            glass.contentView = host
            p.contentView = glass
        } else {
            p.backgroundColor = Theme.ns(\.surfaceRaised)
            p.contentView = host
        }
        p.setContentSize(host.fittingSize)
        self.host = host
        return p
    }

    static func alertFrame() -> NSRect? { Snapshot().alert }

}
