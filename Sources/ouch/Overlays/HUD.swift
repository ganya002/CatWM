// Overlays: the layout-name HUD shown on layout changes.
import AppKit
import SwiftUI

/// Amethyst-style layout name overlay. Layout changes also show the layout, which morphs into the
/// next one when you cycle quickly.
final class HUD {
    static let shared = HUD()
    private var panel: OuchPanel?
    private var host: NSHostingView<HUDView>?
    private let model = HUDModel()
    private var hideWork: DispatchWorkItem?
    /// Room around the card for its shadow; the panel is click-through.
    private static let margin: CGFloat = 30
    /// Something already in the middle of the screen (the tour's card): the HUD shows below it, or
    /// above when there's no room, instead of on top of it.
    var avoid: NSRect?

    func show(_ text: String, layout: Layout? = nil, on screen: NSScreen?) {
        show(text, layout: layout, warning: false, on: screen)
    }

    /// A smaller card with a warning sign, for things that didn't work out (e.g. a window that won't shrink).
    func warn(_ text: String, on screen: NSScreen?) {
        show(text, layout: nil, warning: true, on: screen)
    }

    private func show(_ text: String, layout: Layout?, warning: Bool, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let p = panel ?? makePanel()
        panel = p
        let wasVisible = p.isVisible && p.alphaValue > 0.5
        model.text = text
        model.layout = layout
        model.warning = warning
        // A fresh appearance pops in; updates while it's up just morph in place.
        if !wasVisible { model.pops += 1; PerfMonitor.track("ui:hud", for: 0.5) }
        let host = host ?? NSHostingView(rootView: HUDView(model: model, margin: Self.margin))
        if self.host == nil { self.host = host; p.contentView = host }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        // The margin is transparent, so only the card itself has to clear the other thing.
        if let avoid, frame.insetBy(dx: Self.margin, dy: Self.margin).intersects(avoid) {
            let below = avoid.minY - frame.height + Self.margin - 12
            frame.origin.y = below >= screen.visibleFrame.minY ? below : avoid.maxY - Self.margin + 12
        }
        // Clear of the menu bar and the Dock, however the card had to move.
        p.place(size: frame.size, on: screen, anchor: .origin(frame.origin), inset: EdgeInsets(all: Self.margin))
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p?.animator().alphaValue = 0
            }, completionHandler: {
                // Off screen, not just clear: a new `show` sets the alpha back first, so this leaves it be.
                if let p, p.alphaValue == 0 { p.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (warning ? 1.6 : layout == nil ? 0.8 : 1), execute: work)
    }

    /// Shows over full-screen apps too, like the keyboard help.
    private func makePanel() -> OuchPanel { OuchPanel(role: .hud) }
}

final class HUDModel: ObservableObject {
    @Published var text = ""
    @Published var layout: Layout?
    @Published var warning = false
    @Published var pops = 0
}

/// Confirms a keyboard action in the middle of the screen: a glass Surface with the layout and its
/// name, or a pill with a wiggling warning when something refused. Never interactive.
struct HUDView: View {
    @ObservedObject var model: HUDModel
    let margin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduceMotion = reduceMotion // read here; the animator closure can't touch the environment
        Group {
            if model.warning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .wiggleEffect(value: model.pops)
                    Text(model.text).font(Theme.body(14, .medium)).oneLine().fixedSize()
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .floatingGlass(Capsule())
            } else {
                VStack(spacing: 12) {
                    if let layout = model.layout {
                        LayoutThumbnail(layout: layout, selected: true).frame(width: 120)
                    }
                    Text(model.text).font(Theme.body(22)).tracking(-0.2).oneLine().fixedSize()
                }
                .padding(.horizontal, 24).padding(.top, model.layout == nil ? 16 : 20).padding(.bottom, 16)
                .floatingGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .foregroundStyle(Theme.ink)
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
}
