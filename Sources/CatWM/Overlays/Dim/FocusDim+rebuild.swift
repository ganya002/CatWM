import AppKit
import CatWMKit

extension FocusDim {
    func rebuild() {
        for pair in pairs.values { pair.front.orderOut(nil); pair.spare.orderOut(nil) }
        pairs = [:]
        panelNumbers = []
        target = nil
        update()
    }

    func layoutPanels() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let display = screen.displayID else { continue }
            seen.insert(display)
            let pair = pairs[display] ?? Pair(front: makePanel(screen), spare: makePanel(screen))
            pairs[display] = pair
            for panel in [pair.front, pair.spare] where panel.frame != screen.frame {
                panel.setFrame(screen.frame, display: false)
            }
        }
        for (display, pair) in pairs where !seen.contains(display) {
            pair.front.orderOut(nil); pair.spare.orderOut(nil)
            panelNumbers.remove(pair.front.windowNumber); panelNumbers.remove(pair.spare.windowNumber)
            pairs[display] = nil
        }
    }

    func makePanel(_ screen: NSScreen) -> NSPanel {
        let panel = NSPanel( // style-ok: full-screen click-through dim
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.alphaValue = 0
        panelNumbers.insert(panel.windowNumber)
        style(panel)
        return panel
    }

    func style(_ panel: NSPanel) {
        let amount = dims ? strength : 0, blur = blurs ? radius : 0
        panel.backgroundColor = NSColor.black.withAlphaComponent(max(amount, 0.01))
        if Blur.set(panel.windowNumber, radius: blur) || blur == 0 {
            panel.contentView = NSView()
        } else {
            let effect = NSVisualEffectView()
            effect.material = .fullScreenUI
            effect.blendingMode = .behindWindow
            effect.state = .active
            panel.backgroundColor = .clear
            let tint = NSView()
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(amount).cgColor
            tint.autoresizingMask = [.width, .height]
            effect.addSubview(tint)
            panel.contentView = effect
            tint.frame = effect.bounds
        }
    }
}
