import AppKit
import SwiftUI

/// Amethyst-style layout name overlay. Layout changes also show the layout, which morphs into the
/// next one when you cycle quickly.
final class HUD {
    static let shared = HUD()
    private var panel: NSPanel?
    private var host: NSHostingView<HUDView>?
    private let model = HUDModel()
    private var hideWork: DispatchWorkItem?
    /// Room around the card for its shadow; the panel is click-through.
    private static let margin: CGFloat = 30

    func show(_ text: String, layout: Layout? = nil, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let p = panel ?? makePanel()
        panel = p
        let wasVisible = p.isVisible && p.alphaValue > 0.5
        model.text = text
        model.layout = layout
        // A fresh appearance pops in; updates while it's up just morph in place.
        if !wasVisible { model.pops += 1 }
        let host = host ?? NSHostingView(rootView: HUDView(model: model, margin: Self.margin))
        if self.host == nil { self.host = host; p.contentView = host }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        p.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                          width: size.width, height: size.height), display: true)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + (layout == nil ? 0.8 : 1), execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // drawn by SwiftUI, so it follows the pop
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return p
    }
}

final class HUDModel: ObservableObject {
    @Published var text = ""
    @Published var layout: Layout?
    @Published var pops = 0
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    let margin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduceMotion = reduceMotion // read here; the animator closure can't touch the environment
        VStack(spacing: 12) {
            if let layout = model.layout {
                LayoutThumbnail(layout: layout, selected: true).frame(width: 120, height: 75)
            }
            Text(model.text).font(Theme.heading(28)).fixedSize()
        }
        .padding(.horizontal, 28).padding(.vertical, model.layout == nil ? 16 : 20)
        .background(Blur())
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .keyframeAnimator(initialValue: 1.0, trigger: model.pops) { view, scale in
            view.scaleEffect(reduceMotion ? 1 : scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.9, duration: 0.001)
                SpringKeyframe(1, duration: 0.45, spring: Spring(response: 0.3, dampingRatio: 0.6))
            }
        }
        .padding(margin)
    }

    /// Behind-window blur with rounded corners. A mask image, because a layer corner radius leaves
    /// the blur's edges square.
    private struct Blur: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let v = NSVisualEffectView()
            v.material = .popover
            v.state = .active
            v.blendingMode = .behindWindow
            v.maskImage = roundedMask(radius: 16)
            return v
        }
        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

        private func roundedMask(radius: CGFloat) -> NSImage {
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
    }
}

/// Vim-style mode line ("-- WINDOW --") shown at the bottom of the screen while a submap is active.
final class ModeIndicator {
    static let shared = ModeIndicator()
    private var panel: NSPanel?

    func show(_ mode: String?) {
        guard let mode else {
            guard let p = panel, p.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; p.animator().alphaValue = 0 }) {
                if p.alphaValue == 0 { p.orderOut(nil) }
            }
            return
        }
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
        let end = CGRect(x: v.midX - box.width / 2, y: v.minY + 18, width: box.width, height: box.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if p.isVisible {
            p.setFrame(end, display: true)
        } else {
            // Rises into place; a plain fade under Reduce Motion.
            p.setFrame(reduceMotion ? end : end.offsetBy(dx: 0, dy: -10), display: true)
            p.alphaValue = 0
        }
        p.invalidateShadow()
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            p.animator().alphaValue = 1
            p.animator().setFrame(end, display: true)
        }
    }
}
