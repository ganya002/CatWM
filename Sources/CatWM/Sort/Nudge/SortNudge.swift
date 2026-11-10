import AppKit
import SwiftUI

final class SortNudge {
    static let shared = SortNudge()
    private static let key = "sort.nudged"

    private var panel: CatWMPanel?
    private var hideWork: DispatchWorkItem?
    private let model = SortNudgeModel()

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    func markOffered(_ workspace: String) {
        var days = Instance.defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        days[workspace] = Self.today()
        Instance.defaults.set(days, forKey: Self.key)
    }

    func offer(workspace: String, count: Int, on screen: NSScreen) {
        let manager = WindowManager.shared
        guard panel == nil, manager.tilingEnabled, manager.config.sortNudge > 0, count > manager.config.sortNudge,
              !Onboarding.shared.isRunning, !SortPanel.shared.isOpen, !StatusMenu.shared.isOpen,
              let button = Onboarding.shared.statusButton, let buttonWindow = button.window else { return }
        let days = Instance.defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        guard days[workspace] != Self.today() else { return }
        markOffered(workspace)

        let keys = ShortcutIndex().keys("sort")
        model.workspace = workspace
        model.count = count
        model.keys = keys
        model.sort = { [weak self] in self?.dismiss(); SortPanel.shared.open() }
        model.later = { [weak self] in self?.dismiss() }
        model.never = { [weak self] in
            self?.dismiss()
            Log.attempt("disable Overview tips") {
                try ConfigStore.shared.set(option: ConfigOption.at(\Config.sortNudge), "0")
                manager.applyStoredConfig()
                SettingsWindow.shared.doc.load()
            }
        }
        let host = CatWMHostingView(rootView: SortNudgeView(model: model))
        let size = host.fittingSize
        let buttonFrame = buttonWindow.frame
        let target = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: buttonFrame.midX, y: buttonFrame.midY))
        } ?? screen
        let visible = target.visibleFrame
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        model.caret = min(max(buttonFrame.midX - x, 30), size.width - 30)
        let top = visible.maxY - 4 + (SortNudgeView.inset.top - 10)
        let card = CatWMPanel(role: .card(.floating),
                             frame: CatWMPanel.frame(size: size, on: target,
                                                    anchor: .origin(NSPoint(x: x, y: top - size.height)),
                                                    inset: SortNudgeView.inset).integral)
        card.onClose = { [weak self] in self?.dismiss() }
        card.contentView = host
        card.alphaValue = 0
        card.orderFrontRegardless()
        card.makeKey()
        Motion.group(0.35) { Motion.setAlpha(1, on: card) }
        panel = card
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        guard let card = panel else { return }
        panel = nil
        Motion.group(0.2, changes: { Motion.setAlpha(0, on: card) }, completion: { card.orderOut(nil) })
    }
}

final class SortNudgeModel: ObservableObject {
    @Published var workspace = ""
    @Published var count = 0
    @Published var keys: [String] = []
    @Published var caret: CGFloat = 40
    var sort: () -> Void = {}
    var later: () -> Void = {}
    var never: () -> Void = {}
}

struct SortNudgeView: View {
    @ObservedObject var model: SortNudgeModel
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.popover.room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                OIconButton(symbol: "xmark", label: "Close tip", action: model.later)
                Image(systemName: "lightbulb").font(Theme.symbol(Theme.Icon.large)).foregroundStyle(Theme.accentInk)
                    .breatheEffect().frame(width: 16)
                Text("Workspace \(WorkspaceKey.number(model.workspace)) is packed").font(Theme.heading()).oneLine()
                Spacer(minLength: 4)
            }
            Text("\(model.count) windows on one screen. Split them into workspaces by task.")
                .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            HStack(spacing: 2) {
                ForEach(0..<min(model.count, 40), id: \.self) { _ in Capsule().fill(Theme.tint).frame(height: 4) }
            }
            .padding(.top, Theme.Space.small).padding(.bottom, 12)
            HStack(spacing: 4) {
                OButton("Open Overview", variant: .primary, shortcut: model.keys, action: model.sort)
                OButton("Not now", variant: .ghost, action: model.later)
                Spacer(minLength: 4)
                Button("No more tips", action: model.never).buttonStyle(.plain)
                    .textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .frame(width: 276)
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
        .surface(.medium, caret: .top(model.caret - Self.inset.leading))
        .padding(Self.inset)
        .fixedSize()
        .font(Theme.body())
    }
}
