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
        var days = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        days[workspace] = Self.today()
        UserDefaults.standard.set(days, forKey: Self.key)
    }

    func offer(workspace: String, count: Int, on screen: NSScreen) {
        let manager = WindowManager.shared
        guard panel == nil, manager.tilingEnabled, manager.config.sortNudge > 0, count > manager.config.sortNudge,
              !Onboarding.shared.isRunning, !SortPanel.shared.isOpen, !StatusMenu.shared.isOpen,
              let button = Onboarding.shared.statusButton, let buttonWindow = button.window else { return }
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
            manager.reload(showHUD: false)
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
        animate(0.35) { card.animator().alphaValue = 1 }
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
        animate(0.2, changes: { card.animator().alphaValue = 0 }, completion: { card.orderOut(nil) })
    }
}
