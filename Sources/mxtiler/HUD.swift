import AppKit

/// Amethyst-style layout name overlay.
final class HUD {
    static let shared = HUD()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let label = NSTextField(labelWithString: text)
        label.font = Theme.nsDisplay(28)
        label.textColor = .labelColor
        let size = label.fittingSize
        let box = CGRect(x: 0, y: 0, width: size.width + 56, height: size.height + 32)

        let p = panel ?? makePanel()
        panel = p
        let effect = NSVisualEffectView(frame: box)
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.maskImage = Self.roundedMask(radius: 16) // layer corner radius leaves square blur edges
        // Centre the label with constraints; a bare frame origin left it with a zero-size frame and clipped text.
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
        p.contentView = effect
        p.setFrame(CGRect(x: screen.frame.midX - box.width / 2, y: screen.frame.midY - box.height / 2,
                          width: box.width, height: box.height), display: true)
        p.invalidateShadow()
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                p?.animator().alphaValue = 0
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return p
    }
}

/// Vim-style mode line ("-- WINDOW --") shown at the bottom of the screen while a submap is active.
final class ModeIndicator {
    static let shared = ModeIndicator()
    private var panel: NSPanel?

    func show(_ mode: String?) {
        guard let mode else { panel?.orderOut(nil); return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let label = NSTextField(labelWithString: "-- \(mode.uppercased()) --")
        label.font = Theme.nsMono(13)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        let size = label.fittingSize
        let box = CGRect(x: 0, y: 0, width: size.width + 28, height: size.height + 12)

        let p = panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            return p
        }()
        panel = p
        let bg = NSView(frame: box)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.92).cgColor
        bg.layer?.cornerRadius = box.height / 2
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
        p.contentView = bg
        let v = screen.visibleFrame
        p.setFrame(CGRect(x: v.midX - box.width / 2, y: v.minY + 18, width: box.width, height: box.height), display: true)
        p.invalidateShadow()
        p.orderFrontRegardless()
    }
}
