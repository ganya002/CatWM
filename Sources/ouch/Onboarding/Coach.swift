import AppKit
import SwiftUI

final class Coach {
    enum Target { case center, window, bar, mode }
    enum Event { case mode(String), command(String, String, inMode: Bool), tick }
    enum Ending { case finished, skipped, paused, tutorial }

    struct Step {
        var title: String
        var text: String
        var target = Target.center
        var caps: [String] = []
        var tokens: [String] = []
        var button: String?
        var needsMode = false
        var recall = false
        var count = 1
        var accept: (Event) -> String? = { _ in nil }
        var simulate: (() -> Void)?
        var summary: Summary?
        var final: Bool { summary != nil }
    }

    struct Summary {
        struct Group {
            var title: String
            var column = 1
            var rows: [(caps: [String], label: String)]
        }
        var modeCaps: [String] = []
        var modeName = ""
        var groups: [Group] = []
        var helpKey: String?
        var tutorial = false
    }

    let wm = WindowManager.shared
    private weak var statusButton: NSStatusBarButton?
    private let lesson: Lesson
    private let onEnd: (Ending) -> Void
    let screen: NSScreen

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

    private var panel: OverlayPanel!
    private var host: FirstClickHostingView<CoachCardView>!
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
        if let desk { wm.showWorkspace(desk) }
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
        host = FirstClickHostingView(rootView: CoachCardView(model: model))
        panel = OverlayPanel(frame: .zero, level: .floating, clickThrough: false)
        panel.contentView = host
        enter()

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


    private func launchHelper() {
        guard let exe = Bundle.main.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        let apps = PracticeDesk.pickApps()
        p.arguments = ["practice", String(getpid()), apps.map(\.title).joined(separator: ",")]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.end(.skipped) }
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
        for delay in [0.4, 0.7, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.wm.scheduleRefresh() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, !ended, let desk else { return }
            wm.showWorkspace(desk)
        }
    }

    private var practiceWindows: [AXUIElement] {
        guard helperPID > 0 else { return [] }
        return AXUIElementCreateApplication(helperPID).elements(kAXWindowsAttribute)
    }

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

    var focusedTitle: String? { focusedPractice?.string(kAXTitleAttribute) }

    var visibleTitles: [String] {
        practiceWindows.compactMap { w -> (String, CGFloat)? in
            guard let t = w.string(kAXTitleAttribute), let f = onScreen(w) else { return nil }
            return (t, f.minX)
        }
        .sorted { $0.1 < $1.1 }.map(\.0)
    }

    var mainTitle: String? {
        practiceWindows.compactMap { w -> (String, CGFloat)? in
            guard let t = w.string(kAXTitleAttribute), let f = onScreen(w) else { return nil }
            return (t, f.width * f.height)
        }
        .max { $0.1 < $1.1 }?.0
    }


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
        if case .tick = e {} else { render() }
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
        guard step.button == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.advance() }
    }

    private func revealHint() {
        guard !ended, model.hidden else { return }
        withAnimation(Motion.easeOut) { model.hidden = false }
    }

    private func simulate() {
        guard !done, let run = step.simulate else { return }
        flash()
        if step.needsMode && Hotkeys.shared.submap.isEmpty && !book.mode.isEmpty {
            Hotkeys.shared.setSubmap(book.mode)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
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
        if SortPanel.shared.isOpen { SortPanel.shared.revert() }
        if let panel {
            animate(0.25, changes: { panel.animator().alphaValue = 0 }) { panel.orderOut(nil) }
        }
        if helper?.isRunning == true { helper?.terminate() }
        lesson.ended(how, at: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            wm.practice = nil
            if let original, wm.config.virtualWorkspaces { wm.showWorkspace(original) }
            onEnd(how)
        }
    }


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
        MenuBarTip.shared.suppressed = s.target == .bar
    }

    private func reposition(animated: Bool) {
        guard let panel, !ended, let step else { return }
        let size = host.fittingSize
        let pad = CoachCardView.inset
        let card = NSSize(width: size.width - pad.leading - pad.trailing, height: size.height - pad.top - pad.bottom)
        let v = screen.visibleFrame
        var o = NSPoint(x: v.midX - card.width / 2, y: v.midY - card.height / 2)
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

protocol Lesson: AnyObject {
    func prepare(_ coach: Coach)
    var count: Int { get }
    var startIndex: Int { get }
    var pausable: Bool { get }
    func step(_ i: Int, in coach: Coach) -> Coach.Step
    func ended(_ how: Coach.Ending, at index: Int)
}
