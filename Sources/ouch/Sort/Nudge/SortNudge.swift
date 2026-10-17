import AppKit
import SwiftUI

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
            SettingsWindow.shared.doc.load()
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
        p.onClose = { [weak self] in self?.dismiss() }
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.makeKey()
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
