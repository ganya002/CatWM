import AppKit
import SwiftUI

final class TabDropHint {
    static let shared = TabDropHint()

    private let panel = OuchPanel(role: .overlay(.floating, clickThrough: true))
    private let model = Model()
    private var target: NSRect?
    private var hiding = false

    final class Model: ObservableObject {
        @Published var title = ""
        @Published var pid: pid_t = 0
    }

    private init() {
        let host = NSHostingView(rootView: HintView(model: model))
        panel.contentView = host
    }

    func show(over rect: CGRect, adding window: Window) {
        let title = window.title.flatMap { $0.isEmpty ? nil : $0 }
            ?? NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "Window"
        if model.title != title { model.title = title }
        if model.pid != window.pid { model.pid = window.pid }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        guard frame != target || hiding || !panel.isVisible else { return }
        let appearing = !panel.isVisible || hiding
        target = frame
        hiding = false
        if appearing {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.fast
            context.timingFunction = Motion.Curve.easeOut
            if !appearing { panel.animator().setFrame(frame, display: true) }
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        target = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.fast
            context.timingFunction = Motion.Curve.exit
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.hiding else { return }
            self.hiding = false
            self.panel.orderOut(nil)
        }
    }

    private struct HintView: View {
        @ObservedObject var model: Model

        var body: some View {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.accentSoft)
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                HStack(spacing: Theme.Space.small) {
                    Image(systemName: "plus").font(Theme.symbol(Theme.Icon.small, .bold))
                    Image(nsImage: AppIcons.icon(for: model.pid)).resizable()
                        .frame(width: TabStrip.iconSide, height: TabStrip.iconSide)
                    Text(model.title).font(Theme.body(12, .medium)).oneLine()
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, Theme.Space.medium)
                .frame(height: TabStrip.height - TabStrip.padding * 2)
                .background(Capsule().fill(Theme.accent))
                .padding(.top, Theme.Space.small)
                .padding(.horizontal, Theme.Space.large)
            }
        }
    }
}
