import AppKit

extension FocusDim {
    func rebuild() {
        for p in pairs.values { p.front.orderOut(nil); p.spare.orderOut(nil) }
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
            if pairs[display] == nil { pairs[display] = Pair(front: makePanel(screen), spare: makePanel(screen)) }
            for p in [pairs[display]!.front, pairs[display]!.spare] where p.frame != screen.frame {
                p.setFrame(screen.frame, display: false)
            }
        }
        for (display, p) in pairs where !seen.contains(display) {
            p.front.orderOut(nil); p.spare.orderOut(nil)
            panelNumbers.remove(p.front.windowNumber); panelNumbers.remove(p.spare.windowNumber)
            pairs[display] = nil
        }
    }

    func makePanel(_ screen: NSScreen) -> NSPanel {
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.alphaValue = 0
        panelNumbers.insert(p.windowNumber)
        style(p)
        return p
    }

    func style(_ p: NSPanel) {
        let amount = dims ? strength : 0, blur = blurs ? radius : 0
        p.backgroundColor = NSColor.black.withAlphaComponent(max(amount, 0.01))
        if Blur.set(p.windowNumber, radius: blur) || blur == 0 {
            p.contentView = NSView()
        } else {
            let v = NSVisualEffectView()
            v.material = .fullScreenUI
            v.blendingMode = .behindWindow
            v.state = .active
            p.backgroundColor = .clear
            let tint = NSView()
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(amount).cgColor
            tint.autoresizingMask = [.width, .height]
            v.addSubview(tint)
            p.contentView = v
            tint.frame = v.bounds
        }
    }

}
