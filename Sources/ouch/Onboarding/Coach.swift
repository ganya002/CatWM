// Onboarding: runs keyboard lessons on practice windows with a floating coach card.
import AppKit
import SwiftUI

/// Runs a keyboard lesson on practice windows: the short tour at the end of onboarding, and the
/// longer tutorial from the menu bar. A helper process opens practice windows on a free workspace,
/// the real window manager tiles them, and a coach card floats over them in its own panel, following
/// the focused window, the menu bar item or the mode indicator. A step finishes when the real command
/// runs, so every shortcut is the user's own (read from their config).
final class Coach {
    enum Target { case center, window, bar, mode }
    enum Event { case mode(String), command(String, String, inMode: Bool), tick }
    /// `tutorial`: the tour finished and the user asked for the long tutorial next.
    enum Ending { case finished, skipped, paused, tutorial }

    struct Step {
        var title: String
        var text: String
        var target = Target.center
        /// Keycaps to press. With `tokens` (one per cap), each cap is ticked off on its own.
        var caps: [String] = []
        var tokens: [String] = []
        var button: String?
        var needsMode = false
        /// Recall drills keep the keys behind a Hint button for a few seconds, so you remember first.
        var recall = false
        /// Events that must count, on top of every token in `tokens`.
        var count = 1
        /// The token an event earns, or nil when it doesn't count ("" counts without a token).
        var accept: (Event) -> String? = { _ in nil }
        /// What clicking the keycaps does: runs the step's command for you.
        var simulate: (() -> Void)?
        /// The last step: a cheat sheet of every key the lesson taught.
        var summary: Summary?
        var final: Bool { summary != nil }
    }

    /// The keys on the last card, grouped. All of it comes from the user's own config.
    struct Summary {
        struct Group {
            var title: String
            /// 1 for the left column, 2 for the right.
            var column = 1
            var rows: [(caps: [String], label: String)]
        }
        /// The chord that turns the mode on, shown big above the groups.
        var modeCaps: [String] = []
        var modeName = ""
        var groups: [Group] = []
        /// The keyboard help key, for the footer hint; nil when keyboard help is off.
        var helpKey: String?
        /// Offers the long tutorial next to Finish.
        var tutorial = false
    }

    let wm = WindowManager.shared
    private weak var statusButton: NSStatusBarButton?
    private let lesson: Lesson
    private let onEnd: (Ending) -> Void
    let screen: NSScreen

    // Workspaces: the desk, a second one to visit, one to send a window to, and where the user was.
    private(set) var desk: String?
    private(set) var other: String?
    private(set) var sendTo: String?
    private(set) var original: String?
    private(set) var book = BindBook(binds: [])

    private var index = 0
    private var step: Step!
    private var done = false
    private var hits = 0
    private var seen: Set<String> = []
    private var ended = false
    private var hintWork: DispatchWorkItem?

    private var helper: Process?
    private var helperPID: pid_t = 0

    private var panel: OuchPanel!
    private var host: OuchHostingView<CoachCardView>!
    private let model = CoachModel()
    private var follow: Timer?
    private var target = NSRect.zero

    init(lesson: Lesson, statusButton: NSStatusBarButton?, onEnd: @escaping (Ending) -> Void) {
        self.lesson = lesson
        self.statusButton = statusButton
        self.onEnd = onEnd
        screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func start() {
        if wm.config.virtualWorkspaces {
            original = wm.currentWorkspace
            let used = Set(wm.workspaceSummary().all.filter { $0.windows > 0 || $0.shown }.map(\.name))
            let free = (1...10).map(String.init).filter { !used.contains($0) }
            desk = free.first
            other = free.count > 1 ? free[1] : nil
            sendTo = free.count > 2 ? free[2] : nil
        }
        book = BindBook(binds: wm.config.bindings)
        lesson.prepare(self)
        index = min(lesson.startIndex, lesson.count - 1)
        if let desk { wm.showWorkspace(desk) } // parks the user's windows until the end
        launchHelper()

        wm.onDispatch = { [weak self] d, a, inMode in self?.handle(.command(d, a, inMode: inMode)) }
        wm.onModeChange = { [weak self] name in self?.handle(.mode(name)) }
        Hotkeys.shared.onReturn = { [weak self] in self?.returnPressed() ?? false }

        model.tryKeys = { [weak self] in self?.simulate() }
        model.next = { [weak self] in self?.advance() }
        let ending: Ending = lesson.pausable ? .paused : .skipped
        model.headAction = { [weak self] in self?.end(ending) }
        model.headLabel = lesson.pausable ? "Pause" : "Skip tour"
        model.headSymbol = lesson.pausable ? "pause.fill" : nil
        model.reveal = { [weak self] in self?.revealHint() }
        model.tutorial = { [weak self] in self?.end(.tutorial) }
        host = OuchHostingView(rootView: CoachCardView(model: model))
        panel = OuchPanel(role: .overlay(.floating, clickThrough: false))
        panel.contentView = host
        enter()

        // Let the practice windows open and tile before the card appears over them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !ended else { return }
            reposition(animated: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            animate(0.35) { self.panel.animator().alphaValue = 1 }
            follow = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.handle(.tick)
                self?.reposition(animated: true)
            }
        }
    }

    // MARK: Practice windows

    private func launchHelper() {
        guard let exe = Bundle.main.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        // Picked here so both processes agree on the titles, which is how the windows are told apart.
        let apps = PracticeDesk.pickApps()
        p.arguments = ["practice", String(getpid()), apps.map(\.title).joined(separator: ",")]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.end(.skipped) } // quit from its menu: the lesson is over too
        }
        do { try p.run() } catch {
            Log.info("coach: couldn't open practice windows: \(error.localizedDescription)")
            return
        }
        helper = p
        helperPID = p.processIdentifier
        var map: [String: String] = [:]
        if let desk {
            for (i, app) in apps.enumerated() { map[app.title] = i < PracticeDesk.deskCount ? desk : other ?? desk }
        }
        wm.practice = (helperPID, map)
        // Started with Process rather than LaunchServices, so no launch notification may arrive: look for its windows.
        for delay in [0.4, 0.7, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.wm.scheduleRefresh() }
        }
        // Once they've tiled, focus the desk's first window through the window manager.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, !ended, let desk else { return }
            wm.showWorkspace(desk)
        }
    }

    private var practiceWindows: [AXUIElement] {
        guard helperPID > 0 else { return [] }
        return AXUIElementCreateApplication(helperPID).elements(kAXWindowsAttribute)
    }

    /// A window frame in AppKit coordinates, if enough of it is on this screen (not parked).
    private func onScreen(_ w: AXUIElement) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let f = w.frame
        guard !f.isNull else { return nil }
        let r = NSRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        let seen = screen.frame.intersection(r)
        return seen.width * seen.height > 40_000 ? r : nil
    }

    private var focusedPractice: AXUIElement? {
        helperPID > 0 ? AXUIElementCreateApplication(helperPID).element(kAXFocusedWindowAttribute) : nil
    }

    /// The title of the focused practice window.
    var focusedTitle: String? { focusedPractice?.string(kAXTitleAttribute) }

    /// Titles of the practice windows showing right now, left to right.
    var visibleTitles: [String] {
        practiceWindows.compactMap { w -> (String, CGFloat)? in
            guard let t = w.string(kAXTitleAttribute), let f = onScreen(w) else { return nil }
            return (t, f.minX)
        }
        .sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// The practice window in the main pane: the biggest one showing.
    var mainTitle: String? {
        practiceWindows.compactMap { w -> (String, CGFloat)? in
            guard let t = w.string(kAXTitleAttribute), let f = onScreen(w) else { return nil }
            return (t, f.width * f.height)
        }
        .max { $0.1 < $1.1 }?.0
    }

    // MARK: Progress

    private func enter() {
        hintWork?.cancel()
        done = false
        hits = 0
        seen = []
        step = lesson.step(index, in: self)
        model.hidden = step.recall
        if step.recall {
            let work = DispatchWorkItem { [weak self] in self?.revealHint() }
            hintWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: work)
        }
        render()
    }

    private func handle(_ e: Event) {
        guard !ended, step != nil else { return }
        if case .tick = e {} else { render() } // the mode warning follows the mode
        guard !done, let token = step.accept(e) else { return }
        hits += 1
        let fresh = !token.isEmpty && seen.insert(token).inserted
        if fresh || step.tokens.isEmpty { flash() }
        guard hits >= step.count, Set(step.tokens).isSubset(of: seen) else { return render() }
        done = true
        hintWork?.cancel()
        model.hidden = false
        flash()
        render()
        // A step with a button waits for it; the rest move on by themselves.
        guard step.button == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.advance() }
    }

    private func revealHint() {
        guard !ended, model.hidden else { return }
        withAnimation(Motion.easeOut) { model.hidden = false }
    }

    /// Clicking the keycaps runs the step for you.
    private func simulate() {
        guard !done, let run = step.simulate else { return }
        flash()
        if step.needsMode && Hotkeys.shared.submap.isEmpty && !book.mode.isEmpty {
            Hotkeys.shared.setSubmap(book.mode)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in // let the mode glow show first
                if self?.ended == false { run() }
            }
        } else {
            run()
        }
    }

    private func flash() {
        model.pressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in self?.model.pressed = false }
    }

    /// Return presses the card's button, while you're on the practice windows or the card.
    private func returnPressed() -> Bool {
        guard !ended, step?.button != nil, panel?.isVisible == true else { return false }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front == helperPID || front == getpid() else { return false }
        DispatchQueue.main.async { [weak self] in self?.advance() }
        return true
    }

    private func advance() {
        guard !ended else { return }
        if index + 1 >= lesson.count { return end(.finished) }
        index += 1
        enter()
    }

    func end(_ how: Ending) {
        guard !ended else { return }
        ended = true
        hintWork?.cancel()
        follow?.invalidate()
        wm.onDispatch = nil
        wm.onModeChange = nil
        Hotkeys.shared.onReturn = nil
        statusButton?.highlight(false)
        HUD.shared.avoid = nil
        MenuBarTip.shared.suppressed = false
        Hotkeys.shared.setSubmap("")
        if KeyHelp.shared.isVisible { KeyHelp.shared.hide() }
        if SortPanel.shared.isOpen { SortPanel.shared.revert() } // left open by the Sorting steps
        if let panel {
            animate(0.25, changes: { panel.animator().alphaValue = 0 }) { panel.orderOut(nil) }
        }
        if helper?.isRunning == true { helper?.terminate() }
        lesson.ended(how, at: index)
        // Give the practice windows a moment to go, then bring the user's own workspace back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            wm.practice = nil
            if let original, wm.config.virtualWorkspaces { wm.showWorkspace(original) }
            onEnd(how)
        }
    }

    // MARK: Card

    private func render() {
        guard let s = step else { return }
        model.title = s.title
        model.text = s.text
        model.caps = s.caps
        model.capsDone = s.tokens.count == s.caps.count ? s.tokens.map { seen.contains($0) } : []
        model.recall = s.recall
        model.done = done
        model.button = s.button
        model.summary = s.summary
        model.canHead = !s.final
        let lastIndex = Double(max(1, lesson.count - 1))
        model.progress = min(1, (Double(index) + (done ? 1 : 0)) / lastIndex)
        let modeOff = Hotkeys.shared.submap.isEmpty
        model.warning = s.needsMode && modeOff && !done && !book.mode.isEmpty
            ? "\(book.mode.capitalized) mode is off. Press \(KeyWords.list(book.enterCaps(long: false))) to turn it back on."
            : nil
        statusButton?.highlight(s.target == .bar)
        MenuBarTip.shared.suppressed = s.target == .bar // the card points there itself
    }

    private func reposition(animated: Bool) {
        guard let panel, !ended, let step else { return }
        let size = host.fittingSize
        // The card sits inside the panel with room for its caret and shadow (see CoachCardView).
        let pad = CoachCardView.inset
        let card = NSSize(width: size.width - pad.leading - pad.trailing, height: size.height - pad.top - pad.bottom)
        let v = screen.visibleFrame
        var o = NSPoint(x: v.midX - card.width / 2, y: v.midY - card.height / 2) // card's bottom-left
        var caret = CoachModel.Caret.none
        switch step.target {
        case .center: break
        case .window:
            if let w = focusedPractice, let f = onScreen(w) { o = NSPoint(x: f.midX - card.width / 2, y: f.midY - card.height / 2) }
        case .bar:
            if let b = statusButton?.window?.frame {
                o.x = min(max(b.midX - card.width + 60, v.minX + 16), v.maxX - card.width - 16)
                o.y = b.minY - 10 - card.height
                caret = .up(min(max(b.midX - o.x, 20), card.width - 20))
            }
        case .mode:
            // Low on the screen, out of the way of the glow's fade; nothing there to point at.
            o = NSPoint(x: v.midX - card.width / 2, y: v.minY + 48)
        }
        o.x = min(max(o.x, v.minX + 16), v.maxX - card.width - 16)
        o.y = min(max(o.y, v.minY + 16), v.maxY - card.height - 16)
        if model.caret != caret { model.caret = caret }
        let frame = NSRect(x: o.x - pad.leading, y: o.y - pad.bottom, width: size.width, height: size.height).integral
        HUD.shared.avoid = NSRect(origin: o, size: card)
        guard frame != target else { return }
        let moved = abs(frame.minX - target.minX) > 1 || abs(frame.maxY - target.maxY) > 1
        target = frame
        if animated && moved && panel.isVisible {
            animate(0.45) { panel.animator().setFrame(frame, display: true) }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}

/// A script for the coach: which steps to show, in what order.
protocol Lesson: AnyObject {
    /// Plans the steps once the coach knows the user's keys and which workspaces are free.
    func prepare(_ coach: Coach)
    var count: Int { get }
    var startIndex: Int { get }
    /// Pausable lessons show Pause instead of Skip and remember where you were.
    var pausable: Bool { get }
    /// Builds step `i` as it starts, so a drill can pick its target from the windows as they are now.
    func step(_ i: Int, in coach: Coach) -> Coach.Step
    func ended(_ how: Coach.Ending, at index: Int)
}
