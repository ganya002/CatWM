import AppKit
import SwiftUI

final class HUD {
    static let shared = HUD()
    private var panel: NSPanel?
    private var host: NSHostingView<HUDView>?
    private let model = HUDModel()
    private var hideWork: DispatchWorkItem?
    private static let margin: CGFloat = 30
    var avoid: NSRect?

    func show(_ text: String, layout: Layout? = nil, on screen: NSScreen?) {
        show(text, layout: layout, warning: false, on: screen)
    }

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
        if !wasVisible { model.pops += 1; PerfMonitor.track("ui:hud", for: 0.5) }
        let host = host ?? NSHostingView(rootView: HUDView(model: model, margin: Self.margin))
        if self.host == nil { self.host = host; p.contentView = host }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        if let avoid, frame.insetBy(dx: Self.margin, dy: Self.margin).intersects(avoid) {
            let below = avoid.minY - frame.height + Self.margin - 12
            frame.origin.y = below >= screen.visibleFrame.minY ? below : avoid.maxY - Self.margin + 12
        }
        p.setFrame(frame, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p?.animator().alphaValue = 0
            }, completionHandler: {
                if let p, p.alphaValue == 0 { p.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (warning ? 1.6 : layout == nil ? 0.8 : 1), execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return p
    }
}

final class HUDModel: ObservableObject {
    @Published var text = ""
    @Published var layout: Layout?
    @Published var warning = false
    @Published var pops = 0
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    let margin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduceMotion = reduceMotion
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
