import AppKit
import CatWMKit
import SwiftUI

final class Tips: ObservableObject {
    static let shared = Tips()

    enum TipPlace: Equatable { case settings(String), menuBar, modeBar }

    struct Tip: Equatable {
        let id: String
        let title: String
        var body: String?
        var chords: [[String]] = []
        let place: TipPlace
        var action: (label: String, run: () -> Void)?

        static func == (lhs: Tip, rhs: Tip) -> Bool { lhs.id == rhs.id }
    }

    enum Known: String { case tutorial, keyHelp }

    @Published var settings: Tip?
    var global: Tip?
    var panel: CatWMPanel?
    var hideWork: DispatchWorkItem?
    var pendingWork: DispatchWorkItem?
    var modeEntries = 0

    static let minDaysUsed = 7
    static let cooldown: TimeInterval = 5 * 24 * 3600
    static let paneOpens = 5, menuClicks = 8, modeEntriesNeeded = 15
    static let paneDelay: TimeInterval = 8

    let defaults = Instance.defaults
    static let seenKey = "tips.seen", offKey = "tips.off", clicksKey = "tips.clicks"
    static let daysKey = "tips.days", lastKey = "tips.last", panesKey = "tips.panes"

    var enabled: Bool {
        get { !defaults.bool(forKey: Self.offKey) }
        set {
            defaults.set(!newValue, forKey: Self.offKey)
            if newValue {
                for key in [Self.seenKey, Self.clicksKey, Self.panesKey, Self.lastKey] {
                    defaults.removeObject(forKey: key)
                }
            } else {
                dismissAll()
            }
        }
    }

    var seen: Set<String> { Set(defaults.stringArray(forKey: Self.seenKey) ?? []) }

    var daysUsed: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var days = Set(defaults.stringArray(forKey: Self.daysKey) ?? [])
        if days.insert(formatter.string(from: Date())).inserted { defaults.set(Array(days), forKey: Self.daysKey) }
        return days.count
    }

    var rested: Bool {
        Date().timeIntervalSince1970 - defaults.double(forKey: Self.lastKey) >= Self.cooldown
    }
}

extension Tips {
    func dismissSettings() {
        guard settings != nil else { return }
        withAnimation(Motion.easeOut) { settings = nil }
    }

    func showPanel(_ tip: Tip) -> Bool {
        let host = CatWMHostingView(rootView: TipView(tip: tip, inset: TipView.panelInset))
        let size = host.fittingSize
        guard var screen = WindowManager.shared.focusedScreen ?? CatWMPanel.pointerScreen() else { return false }
        let visible = screen.visibleFrame
        var frame: NSRect
        var caret: Caret
        switch tip.place {
        case .menuBar:
            guard let button = Onboarding.shared.statusButton?.window?.frame,
                  let target = NSScreen.screens.first(where: {
                      $0.frame.contains(NSPoint(x: button.midX, y: button.midY))
                  }) else { return false }
            let targetVisible = target.visibleFrame
            var x = button.midX - size.width / 2
            x = min(max(x, targetVisible.minX + 8), targetVisible.maxX - size.width - 8)
            caret = .top(min(max(button.midX - x, 30), size.width - 30) - TipView.panelInset.leading)
            frame = NSRect(x: x, y: targetVisible.maxY - 4 + (TipView.panelInset.top - 10) - size.height,
                           width: size.width, height: size.height)
            screen = target
        default:
            caret = .bottom
            frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 18 + 28 + 16 - TipView.panelInset.bottom,
                           width: size.width, height: size.height)
        }
        host.rootView = TipView(tip: tip, inset: TipView.panelInset, caret: caret)
        let panelFrame = CatWMPanel.frame(size: frame.size, on: screen, anchor: .origin(frame.origin),
                                         inset: TipView.panelInset).integral
        let shown = CatWMPanel(role: .overlay(.floating, clickThrough: false), frame: panelFrame)
        shown.contentView = host
        shown.alphaValue = 0
        shown.orderFrontRegardless()
        Motion.group(0.35) { Motion.setAlpha(1, on: shown) }
        panel?.orderOut(nil)
        panel = shown
        global = tip
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissGlobal() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
        return true
    }

    func dismissGlobal() {
        hideWork?.cancel()
        global = nil
        guard let hidden = panel else { return }
        panel = nil
        Motion.group(0.2, changes: { Motion.setAlpha(0, on: hidden) }, completion: { hidden.orderOut(nil) })
    }
}
