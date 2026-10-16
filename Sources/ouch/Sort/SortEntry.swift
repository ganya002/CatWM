// Sort: ways into Sort Windows (crowded-workspace tip, the offer at the end of the tour).
import AppKit
import SwiftUI

// Ways into Sort Windows besides the menu and the bind: a tip under the menu bar icon when a workspace
// is packed, and the card that closes the keyboard tour.

// MARK: - Crowded tip

/// "Workspace 1 is packed": a Surface `md` hanging under the menu bar icon, at most once a day per
/// workspace, never while the tour runs.
final class SortNudge {
    static let shared = SortNudge()
    private static let key = "sort.nudged"

    private var panel: OuchPanel?
    private var hideWork: DispatchWorkItem?
    private let model = SortNudgeModel()

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// Counts as shown for today, so the tour's own offer isn't followed by this one.
    func markOffered(_ workspace: String) {
        var days = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        days[workspace] = Self.today()
        UserDefaults.standard.set(days, forKey: Self.key)
    }

    func offer(workspace: String, count: Int, on screen: NSScreen) {
        let wm = WindowManager.shared
        guard panel == nil, wm.tilingEnabled, wm.config.sortNudge > 0, count > wm.config.sortNudge, !Onboarding.shared.isRunning,
              !SortPanel.shared.isOpen, !StatusMenu.shared.isOpen,
              let button = Onboarding.shared.statusButton, let bw = button.window else { return }
        let days = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
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
            Config.write(option: "sort-nudge", "0")
            SettingsWindow.shared.doc.load() // an open Settings window must not write the old value back
            wm.reload(showHUD: false)
        }
        let host = OuchHostingView(rootView: SortNudgeView(model: model))
        let size = host.fittingSize
        let b = bw.frame
        let target = NSScreen.screens.first { $0.frame.contains(NSPoint(x: b.midX, y: b.midY)) } ?? screen
        let v = target.visibleFrame
        var x = b.midX - size.width / 2
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
        model.caret = min(max(b.midX - x, 30), size.width - 30)
        let top = v.maxY - 4 + (SortNudgeView.inset.top - 10)
        let p = OuchPanel(role: .card(.floating),
                          frame: OuchPanel.frame(size: size, on: target, anchor: .origin(NSPoint(x: x, y: top - size.height)),
                                                 inset: SortNudgeView.inset).integral)
        p.onClose = { [weak self] in self?.dismiss() } // Esc, ⌘W and ⌘Q: "Not now", never quit Ouch
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.makeKey() // Return sorts
        animate(0.35) { p.animator().alphaValue = 1 }
        panel = p
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        guard let p = panel else { return }
        panel = nil
        animate(0.2, changes: { p.animator().alphaValue = 0 }) { p.orderOut(nil) }
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

private struct SortNudgeView: View {
    @ObservedObject var model: SortNudgeModel
    static let inset = EdgeInsets(top: 18, leading: 32, bottom: 44, trailing: 32)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentInk)
                    .breatheEffect().frame(width: 16)
                Text("Workspace \(model.workspace) is packed").font(Theme.heading()).oneLine()
                Spacer(minLength: 4)
                OIconButton(symbol: "xmark", label: "Close tip", action: model.later).padding(.trailing, -4)
            }
            Text("\(model.count) windows on one screen. Split them into workspaces by task.")
                .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            HStack(spacing: 2) {
                ForEach(0..<min(model.count, 40), id: \.self) { _ in Capsule().fill(Theme.tint).frame(height: 4) }
            }
            .padding(.top, 10).padding(.bottom, 12)
            HStack(spacing: 4) {
                OButton("Sort windows", variant: .primary, shortcut: model.keys, action: model.sort)
                OButton("Not now", variant: .ghost, action: model.later)
                Spacer(minLength: 4)
                Button("No more tips", action: model.never).buttonStyle(.plain)
                    .font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .frame(width: 276)
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
        .surface(.md, caret: .top(model.caret - Self.inset.leading))
        .padding(Self.inset)
        .fixedSize()
        .font(Theme.body())
    }
}

// MARK: - After the tour

/// The tour's closing card: the user's windows came back crowded onto one workspace, sort them?
final class SortOffer {
    static let shared = SortOffer()
    private var panel: OuchPanel?
    private var finish: ((Bool) -> Void)?
    private var timeout: DispatchWorkItem?

    func show(button: NSStatusBarButton?, on screen: NSScreen,
              done: @escaping (_ sort: Bool) -> Void) {
        finish = done
        let view = SortOfferView(caret: 0) { [weak self] in self?.end($0) }
        var host = OuchHostingView(rootView: view)
        let size = host.fittingSize
        let v = screen.visibleFrame
        // Hangs under the menu bar icon like the tour's own cards do.
        var x = v.midX - size.width / 2, y = v.maxY - size.height - 16
        var caret: CGFloat = SortOfferView.width / 2 // the card is centred when there's no icon to hang under
        if let b = button?.window?.frame {
            let card = SortOfferView.width
            let left = min(max(b.midX - card + 60, v.minX + 16), v.maxX - card - 16)
            x = left - SortOfferView.inset.leading
            y = b.minY - 10 - (size.height - SortOfferView.inset.top - SortOfferView.inset.bottom) - SortOfferView.inset.bottom
            caret = min(max(b.midX - left, 20), card - 20)
        }
        host = OuchHostingView(rootView: SortOfferView(caret: caret) { [weak self] in
            self?.end($0)
        })
        let p = OuchPanel(role: .overlay(.floating, clickThrough: false),
                          frame: OuchPanel.frame(size: size, on: screen, anchor: .origin(NSPoint(x: x, y: y)), inset: SortOfferView.inset).integral)
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        animate(0.35) { p.animator().alphaValue = 1 }
        panel = p
        // Left alone, it counts as "Keep as is".
        let work = DispatchWorkItem { [weak self] in self?.end(false) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func end(_ sort: Bool) {
        timeout?.cancel()
        timeout = nil
        guard let p = panel else { return }
        panel = nil
        let done = finish
        finish = nil
        animate(0.25, changes: { p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        done?(sort)
    }
}

private struct SortOfferView: View {
    let caret: CGFloat
    let choose: (Bool) -> Void
    static let width: CGFloat = 344
    static let inset = EdgeInsets(top: 32, leading: 52, bottom: 68, trailing: 52)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
            }
            .frame(minHeight: 22)
            Text("Your workspace is crowded").font(Theme.body(22))
                .tracking(-0.2).fixedSize(horizontal: false, vertical: true).padding(.top, 12).padding(.bottom, 4)
            HStack(spacing: 4) {
                OButton("Sort my windows", variant: .primary, shortcut: ["↩"]) { choose(true) }
                    .keyboardShortcut(.defaultAction)
                OButton("Keep as is", variant: .ghost) { choose(false) }
            }
            .padding(.top, 20)
            Capsule().fill(Theme.accent).frame(height: 3).padding(.top, 14)
        }
        .frame(width: Self.width - 40)
        .surface(.lg, caret: .top(caret))
        .padding(Self.inset)
        .fixedSize()
    }
}
