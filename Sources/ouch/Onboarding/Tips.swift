// Onboarding: one-time tips after onboarding (in Settings, under the menu bar item, above the mode bar).
import AppKit
import SwiftUI

/// Small tips that turn up once, where they're useful, after onboarding: in Settings beside the pane
/// they're about, under the menu bar item, or above the mode bar. Each is a Surface `md` with a
/// breathing lightbulb, a close button and "No more tips". Never more than one at a time, never
/// during a lesson, and each is shown only once. They're rare on purpose: none until Ouch has been
/// used on a week of different days, then at most one every five days, and each waits until what
/// it's about has come up a few times.
final class Tips: ObservableObject {
    static let shared = Tips()

    struct Tip: Equatable {
        enum Place: Equatable { case settings(String), menuBar, modeBar }
        let id: String
        let title: String
        var body: String?
        /// Keys to show, each chord after the first read as "then".
        var chords: [[String]] = []
        let place: Place
        /// A primary button that does something, e.g. "Start tutorial"; otherwise "Got it".
        var action: (label: String, run: () -> Void)?

        static func == (a: Tip, b: Tip) -> Bool { a.id == b.id }
    }

    enum Known: String { case tutorial, keyHelp }

    /// The tip showing inside Settings, if any.
    @Published private(set) var settings: Tip?
    private var global: Tip?
    private var panel: OuchPanel?
    private var hideWork: DispatchWorkItem?
    private var pendingWork: DispatchWorkItem?
    private var modeEntries = 0

    /// Pacing. A day counts when Ouch runs on it.
    static let minDaysUsed = 7
    static let cooldown: TimeInterval = 5 * 24 * 3600
    /// How often a pane must be opened, a menu command clicked, or window mode entered (this run)
    /// before its tip, and how long the pane must stay open first.
    static let paneOpens = 5, menuClicks = 8, modeEntriesNeeded = 15
    static let paneDelay: TimeInterval = 8

    private let defaults = UserDefaults.standard
    private static let seenKey = "tips.seen", offKey = "tips.off", clicksKey = "tips.clicks"
    private static let daysKey = "tips.days", lastKey = "tips.last", panesKey = "tips.panes"

    var enabled: Bool {
        get { !defaults.bool(forKey: Self.offKey) }
        set {
            defaults.set(!newValue, forKey: Self.offKey)
            if newValue {
                for k in [Self.seenKey, Self.clicksKey, Self.panesKey, Self.lastKey] { defaults.removeObject(forKey: k) }
            } else {
                dismissAll()
            }
        }
    }

    private var seen: Set<String> { Set(defaults.stringArray(forKey: Self.seenKey) ?? []) }

    func markSeen(_ id: String) {
        guard !seen.contains(id) else { return }
        defaults.set(Array(seen.union([id])), forKey: Self.seenKey)
    }

    func markSeen(_ k: Known) { markSeen(k.rawValue) }

    /// Notes today as a day of use, and counts them.
    private var daysUsed: Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var days = Set(defaults.stringArray(forKey: Self.daysKey) ?? [])
        if days.insert(f.string(from: Date())).inserted { defaults.set(Array(days), forKey: Self.daysKey) }
        return days.count
    }

    private var rested: Bool {
        Date().timeIntervalSince1970 - defaults.double(forKey: Self.lastKey) >= Self.cooldown
    }

    /// At launch: counts the day, and once Ouch has been used for a while, points at the tutorial.
    func launched() {
        _ = daysUsed
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            if !TutorialLesson.finishedOnce, TutorialLesson.paused == nil { self?.show(.tutorial) }
        }
    }

    private func canShow(_ id: String) -> Bool {
        enabled && daysUsed >= Self.minDaysUsed && rested && Onboarding.isDone && !Onboarding.shared.isRunning && !seen.contains(id) && settings == nil && global == nil
            && !SortPanel.shared.isOpen
    }

    // MARK: Triggers

    /// Shows one of the fixed tips (the tutorial pointer after onboarding).
    func show(_ k: Known) {
        switch k {
        case .tutorial:
            guard canShow(k.rawValue) else { return }
            present(Tip(id: k.rawValue, title: "Make the keys stick",
                        body: "Keyboard Tutorial, in this menu, drills them a chapter at a time.",
                        place: .menuBar, action: ("Start tutorial", { Onboarding.shared.startTutorial() })))
        case .keyHelp:
            let keys = ShortcutIndex()
            guard canShow(k.rawValue), WindowManager.shared.config.keyboardHelp, !Hotkeys.shared.submap.isEmpty else { return }
            let helpKey = WindowManager.shared.config.keyboardHelpKey
            let held = keys.modeChord.first.map { " Or hold \($0) after you enter." } ?? ""
            present(Tip(id: k.rawValue, title: "See every key", body: "In window mode, \(helpKey) shows what every key does.\(held)",
                        chords: [[helpKey]], place: .modeBar))
        }
    }

    /// Window mode turned on or off. After a few entries without ever opening the keyboard help, suggest it.
    func modeChanged(_ name: String) {
        pendingWork?.cancel()
        if name.isEmpty {
            if case .modeBar = global?.place { dismissGlobal() }
            return
        }
        modeEntries += 1
        guard modeEntries >= Self.modeEntriesNeeded, canShow(Known.keyHelp.rawValue) else { return }
        let work = DispatchWorkItem { [weak self] in self?.show(.keyHelp) }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// A menu command with a shortcut was clicked. The third time, show its key.
    func clicked(id: String, label: String, shortcut: [String]) {
        guard !shortcut.isEmpty, enabled, Onboarding.isDone else { return }
        var counts = defaults.dictionary(forKey: Self.clicksKey) as? [String: Int] ?? [:]
        counts[id, default: 0] += 1
        defaults.set(counts, forKey: Self.clicksKey)
        let tipID = "clicked.\(id)"
        guard counts[id, default: 0] >= Self.menuClicks, canShow(tipID) else { return }
        // Window-mode keys are plain letters (maybe with ⇧); those need the mode chord first.
        let keys = ShortcutIndex()
        let global = shortcut.contains { ["⌘", "⌥", "⌃"].contains($0) }
        let chords = global || keys.modeChord.isEmpty ? [shortcut] : [keys.modeChord, shortcut]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in // after the menu has closed
            guard let self, canShow(tipID) else { return }
            present(Tip(id: tipID, title: "\(label) has a key", body: "Faster than the menu.",
                        chords: chords, place: .menuBar))
        }
    }

    /// A Settings pane came into view.
    func paneShown(_ pane: Pane) {
        if let s = settings, s.place != .settings("pane.\(pane.rawValue)") { dismissSettings() }
        let keys = ShortcutIndex()
        let chord = keys.modeChord
        let tip: Tip?
        switch pane {
        case .shortcuts:
            tip = Tip(id: "settings.shortcuts", title: "Two sets of keys",
                      body: "Global keys work anywhere. The rest work in window mode, so they never clash with typing.",
                      chords: chord.isEmpty ? [] : [chord], place: .settings("pane.\(pane.rawValue)"))
        case .layout:
            let next = keys.keys("cyclelayout", "next")
            tip = next.isEmpty ? nil : Tip(id: "settings.layout", title: "Step through these layouts",
                                           body: "In window mode, \(next.joined()) steps through this list.",
                                           chords: chord.isEmpty ? [next] : [chord, next], place: .settings("pane.\(pane.rawValue)"))
        case .windows:
            let float = keys.keys("togglefloating")
            tip = float.isEmpty ? nil : Tip(id: "settings.windows", title: "Float a single window",
                                            body: "This list floats whole apps. \(float.joined()) in window mode floats one window.",
                                            chords: chord.isEmpty ? [float] : [chord, float], place: .settings("pane.\(pane.rawValue)"))
        default:
            tip = nil
        }
        guard let tip, canShow(tip.id) else { return }
        var opens = defaults.dictionary(forKey: Self.panesKey) as? [String: Int] ?? [:]
        opens[tip.id, default: 0] += 1
        defaults.set(opens, forKey: Self.panesKey)
        guard opens[tip.id, default: 0] >= Self.paneOpens else { return }
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, canShow(tip.id), SettingsWindow.shared.ui.pane == pane else { return }
            present(tip)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.paneDelay, execute: work)
    }

    /// Settings closed.
    func settingsClosed() {
        pendingWork?.cancel()
        dismissSettings()
    }

    // MARK: Showing

    private func present(_ tip: Tip) {
        switch tip.place {
        case .settings:
            withAnimation(Motion.easeOut) { settings = tip }
        case .menuBar, .modeBar:
            guard showPanel(tip) else { return } // nowhere to show it: keep the tip and today's slot
        }
        markSeen(tip.id)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastKey)
    }

    func dismiss(_ tip: Tip) {
        if settings == tip { dismissSettings() } else if global == tip { dismissGlobal() }
    }

    func noMore() {
        enabled = false
    }

    func dismissAll() {
        pendingWork?.cancel()
        dismissSettings()
        dismissGlobal()
    }

    private func dismissSettings() {
        guard settings != nil else { return }
        withAnimation(Motion.easeOut) { settings = nil }
    }

    private func showPanel(_ tip: Tip) -> Bool {
        let host = OuchHostingView(rootView: TipView(tip: tip, inset: TipView.panelInset))
        let size = host.fittingSize
        var screen = WindowManager.shared.focusedScreen ?? OuchPanel.pointerScreen()
        let v = screen.visibleFrame
        var frame: NSRect
        var caret: Caret
        switch tip.place {
        case .menuBar:
            guard let b = Onboarding.shared.statusButton?.window?.frame,
                  let target = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: b.midX, y: b.midY)) }) else { return false }
            let tv = target.visibleFrame
            var x = b.midX - size.width / 2
            x = min(max(x, tv.minX + 8), tv.maxX - size.width - 8)
            caret = .top(min(max(b.midX - x, 30), size.width - 30) - TipView.panelInset.leading)
            frame = NSRect(x: x, y: tv.maxY - 4 + (TipView.panelInset.top - 10) - size.height, width: size.width, height: size.height)
            screen = target
        default:
            caret = .bottom
            frame = NSRect(x: v.midX - size.width / 2, y: v.minY + 18 + 28 + 16 - TipView.panelInset.bottom,
                           width: size.width, height: size.height)
        }
        host.rootView = TipView(tip: tip, inset: TipView.panelInset, caret: caret)
        let p = OuchPanel(role: .overlay(.floating, clickThrough: false),
                          frame: OuchPanel.frame(size: frame.size, on: screen, anchor: .origin(frame.origin), inset: TipView.panelInset).integral)
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        animate(0.35) { p.animator().alphaValue = 1 }
        panel?.orderOut(nil)
        panel = p
        global = tip
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissGlobal() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
        return true
    }

    private func dismissGlobal() {
        hideWork?.cancel()
        global = nil
        guard let p = panel else { return }
        panel = nil
        animate(0.2, changes: { p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }
}

// MARK: - View

/// One tip: Surface `md` with a breathing lightbulb, a title, a line or two, its keys, and actions.
struct TipView: View {
    let tip: Tips.Tip
    var inset = EdgeInsets()
    var caret: Caret = .none
    /// Room in a panel for the caret and the popover shadow.
    static let panelInset = EdgeInsets(top: 18, leading: 32, bottom: 44, trailing: 32)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb").font(Theme.symbol(Theme.Icon.lg)).foregroundStyle(Theme.accentInk)
                    .breatheEffect().frame(width: 16)
                Text(tip.title).font(Theme.heading()).oneLine()
                Spacer(minLength: 4)
                OIconButton(symbol: "xmark", label: "Close tip") { Tips.shared.dismiss(tip) }.padding(.trailing, -4)
            }
            if let body = tip.body {
                Text(body).font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).lineSpacing(1.5)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            if !tip.chords.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(tip.chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .padding(.top, 10)
            }
            HStack(spacing: 4) {
                OButton("No more tips", variant: .ghost, size: .sm) { Tips.shared.noMore() }
                    .padding(.leading, -11) // the label lines up with the text above
                Spacer(minLength: 8)
                if let action = tip.action {
                    OButton(action.label, variant: .primary) {
                        Tips.shared.dismiss(tip)
                        action.run()
                    }
                } else {
                    OButton("Got it", variant: .primary) { Tips.shared.dismiss(tip) }
                }
            }
            .padding(.top, 12)
        }
        .frame(width: 276)
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
        .surface(.md, caret: caret)
        .padding(inset)
        .fixedSize()
        .font(Theme.body())
    }
}

// MARK: - Anchors in Settings

/// Settings views mark what a tip can point at; the root view places the tip beside it.
struct TipAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tipAnchor(_ id: String) -> some View {
        anchorPreference(key: TipAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// Draws the Settings tip to the right of its anchor, the caret pointing back at it.
struct SettingsTipLayer: View {
    @ObservedObject var tips = Tips.shared
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { g in
            if let tip = tips.settings, case .settings(let id) = tip.place, let a = anchors[id] {
                let r = g[a]
                if r.midY < g.size.height * 0.6 {
                    // The caret sits level with the title row, so that row lines up with the anchor.
                    TipView(tip: tip, caret: .leading(20))
                        .offset(x: r.maxX + 14, y: r.midY - 20)
                        .transition(.opacity.combined(with: .offset(x: -6)))
                } else {
                    // Low in the window: grow upwards from the anchor so the tip stays inside.
                    TipView(tip: tip, caret: .leadingBottom(24))
                        .frame(height: r.midY + 24, alignment: .bottom)
                        .offset(x: r.maxX + 14)
                        .transition(.opacity.combined(with: .offset(x: -6)))
                }
            }
        }
    }
}
