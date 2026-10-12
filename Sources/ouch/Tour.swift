import AppKit
import SwiftUI

/// The keyboard tour. A helper process opens practice windows on a free workspace, the real window
/// manager tiles them, and a coach card floats over them in its own panel, following the focused
/// window, the menu bar item or the mode indicator. Steps finish when the real command runs, so
/// every shortcut is the user's own (read from their config).
final class Tour {
    private enum ID { case intro, mode, focus, move, layout, visit, back, send, exit, global, final }
    private enum Target { case center, window, bar, mode }
    private enum Event { case mode(String), command(String, String, inMode: Bool) }

    private struct Step {
        let id: ID
        var kicker: String
        var title: String
        var text: String
        var target = Target.center
        var caps: [String] = []
        var button: String?
        var needsMode = false
    }

    private let wm = WindowManager.shared
    private weak var statusButton: NSStatusBarButton?
    private let onEnd: () -> Void
    private let screen: NSScreen

    private var steps: [Step] = []
    private var index = 0
    private var done = false
    private var counter = 0
    private var ended = false

    // Workspaces: the desk, a second one to visit, one to send a window to, and where the user was.
    private var desk: String?
    private var other: String?
    private var sendTo: String?
    private var original: String?
    private var mode = ""
    private var finalRows: [(caps: [String], label: String)] = []

    private var helper: Process?
    private var helperPID: pid_t = 0
    private var checklist: Set<Int> = []

    private var panel: OverlayPanel!
    private var host: FirstClickHostingView<CoachCardView>!
    private let model = CoachModel()
    private var follow: Timer?
    private var target = NSRect.zero

    init(statusButton: NSStatusBarButton?, onEnd: @escaping () -> Void) {
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
        steps = makeSteps(wm.config.bindings)
        if let desk { wm.showWorkspace(desk) } // parks the user's windows until the end
        launchHelper()

        wm.onDispatch = { [weak self] d, a, inMode in self?.handle(.command(d, a, inMode: inMode)) }
        wm.onModeChange = { [weak self] name in self?.handle(.mode(name)) }

        model.tryKeys = { [weak self] in self?.simulate() }
        model.next = { [weak self] in self?.advance() }
        model.skip = { [weak self] in self?.end() }
        host = FirstClickHostingView(rootView: CoachCardView(model: model))
        panel = OverlayPanel(frame: .zero, level: .floating, clickThrough: false)
        panel.contentView = host
        render()

        // Let the practice windows open and tile before the card appears over them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !ended else { return }
            reposition(animated: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            animate(0.35) { self.panel.animator().alphaValue = 1 }
            follow = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.reposition(animated: true) }
        }
    }

    // MARK: Practice windows

    private func launchHelper() {
        guard let exe = Bundle.main.executableURL else { return }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["practice", String(getpid())]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.end() } // quit from its menu: the tour is over too
        }
        do { try p.run() } catch {
            Log.info("tour: couldn't open practice windows: \(error.localizedDescription)")
            return
        }
        helper = p
        helperPID = p.processIdentifier
        var map: [String: String] = [:]
        if let desk {
            for k in [PracticeDesk.Kind.terminal, .notes, .docs] { map[PracticeDesk.title(k)] = desk }
            map[PracticeDesk.title(.inbox)] = other ?? desk
        }
        wm.practice = (helperPID, map)
        // Started with Process rather than LaunchServices, so no launch notification may arrive: look for its windows.
        for delay in [0.4, 0.7, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.wm.scheduleRefresh() }
        }
        // Once they've tiled, focus the desk's first window through the window manager.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, !ended, let desk else { return }
            wm.showWorkspace(desk)
        }
    }

    /// The focused practice window, in AppKit coordinates, if it's on screen (not parked).
    private func focusedPracticeFrame() -> NSRect? {
        guard helperPID > 0, let primary = NSScreen.screens.first else { return nil }
        let app = AXUIElementCreateApplication(helperPID)
        guard let w = app.element(kAXFocusedWindowAttribute) else { return nil }
        let f = w.frame
        guard !f.isNull else { return nil }
        let r = NSRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        let seen = screen.frame.intersection(r)
        return seen.width * seen.height > 40_000 ? r : nil
    }

    // MARK: Steps

    private func makeSteps(_ binds: [KeyBinding]) -> [Step] {
        func find(_ submap: String, _ dispatcher: [String], _ arg: String? = nil) -> KeyBinding? {
            binds.first { b in
                b.submap == submap && dispatcher.contains(b.dispatcher) && (arg.map { Self.same(b.arg, $0) } ?? true)
            }
        }
        let enter = binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && !["", "reset"].contains($0.arg.lowercased()) }
        mode = enter?.arg ?? ""
        let dirs = ["l", "d", "u", "r"].compactMap { find(mode, ["movefocus"], $0) }
        let moveL = find(mode, ["movewindow", "swapwindow"], "l"), moveR = find(mode, ["movewindow", "swapwindow"], "r")
        let next = find(mode, ["cyclelayout"], "next"), prev = find(mode, ["cyclelayout"], "prev")
        let visit = other.flatMap { find(mode, ["workspace"], $0) }
        let back = desk.flatMap { find(mode, ["workspace"], $0) }
        let send = sendTo.flatMap { find(mode, ["movetoworkspace", "movetoworkspacesilent"], $0) }
        let exits = binds.filter { $0.submap == mode && $0.dispatcher == "submap" && ["", "reset"].contains($0.arg.lowercased()) && $0.mods.isEmpty }
        let global = desk.flatMap { find("", ["workspace"], $0) }

        var out: [Step] = []
        let deskText: String
        if let desk, let other {
            deskText = "We opened three pretend windows on workspace \(desk) and one on workspace \(other)."
                + (original.map { " Your own windows wait on workspace \($0) until you're done." } ?? "")
        } else {
            deskText = "We opened four pretend windows to practise on. Nothing you do here changes your own apps."
        }
        out.append(Step(id: .intro, kicker: "Keyboard tour", title: "Meet your practice desk", text: deskText, button: "Show me"))

        if let enter, !mode.isEmpty {
            let modeName = mode.capitalized
            out.append(Step(id: .mode, kicker: "\(modeName) mode", title: "Enter \(mode.lowercased()) mode",
                            text: "One shortcut turns it on. Then single keys move your windows. When the mode is off, those keys go to your apps as usual.",
                            caps: Self.caps(enter, long: true)))
            if dirs.count >= 2 {
                let keys = dirs.map { Self.keyLabel($0.keyCode, long: false) }
                out.append(Step(id: .focus, kicker: "Focus", title: "Move focus, vim style",
                                text: "\(Self.list(keys)) move focus left, down, up and right. Try a couple of them.",
                                target: .window, caps: keys, needsMode: true))
                finalRows.append(([keys.joined(separator: " ")], "Move focus"))
            }
            if let moveL, let moveR {
                let mods = Self.modLabels(moveL.mods, long: true)
                out.append(Step(id: .move, kicker: "Move", title: "Move the window itself",
                                text: "Hold \(Self.modWords(moveL.mods)) with a direction to swap the focused window with its neighbour.",
                                target: .window, caps: mods + [Self.keyLabel(moveL.keyCode, long: false), Self.keyLabel(moveR.keyCode, long: false)],
                                needsMode: true))
                finalRows.append((Self.modLabels(moveL.mods, long: false) + [dirs.map { Self.keyLabel($0.keyCode, long: false) }.joined(separator: " ")],
                                  "Move the window"))
            }
            if let next {
                let keys = [next, prev].compactMap { $0 }.map { Self.keyLabel($0.keyCode, long: false) }
                out.append(Step(id: .layout, kicker: "Layouts", title: "Try another layout",
                                text: "\(keys[0]) steps forward through your layouts\(keys.count > 1 ? " and \(keys[1]) steps back" : ""). Press \(keys[0]) a couple of times.",
                                target: .window, caps: keys, needsMode: true))
                finalRows.append((keys, keys.count > 1 ? "Next / previous layout" : "Next layout"))
            }
            if let visit, let back, let other, let desk {
                let key = Self.keyLabel(visit.keyCode, long: false)
                out.append(Step(id: .visit, kicker: "Workspaces", title: "Workspaces are separate desks",
                                text: "Each display shows one workspace, and each one keeps its own layout and focused window. The menu bar shows them all, with yours filled in. Press \(key) to visit workspace \(other).",
                                target: .bar, caps: Self.caps(visit, long: true), needsMode: true))
                out.append(Step(id: .back, kicker: "Workspaces", title: "Nothing was closed",
                                text: "Windows on hidden workspaces are parked just off-screen in a corner. Press \(Self.keyLabel(back.keyCode, long: false)) to bring workspace \(desk) back.",
                                target: .bar, caps: Self.caps(back, long: true), needsMode: true))
                finalRows.append((["1–0"], "Switch workspace"))
            }
            if let send, let sendTo {
                out.append(Step(id: .send, kicker: "Workspaces", title: "Send a window somewhere else",
                                text: "\(Self.modWords(send.mods)) with a number moves the focused window to that workspace\(send.dispatcher == "movetoworkspace" ? ", and you go with it" : ""). Send this one to \(sendTo).",
                                target: .window, caps: Self.caps(send, long: true), needsMode: true))
                finalRows.append((Self.modLabels(send.mods, long: false) + ["1–0"], "Send window to a workspace"))
            }
            let exitKeys = exits.map { Self.keyLabel($0.keyCode, long: false) }
            out.append(Step(id: .exit, kicker: "\(modeName) mode", title: "Leave \(mode.lowercased()) mode",
                            text: (exitKeys.isEmpty ? "Clicking anywhere" : "\(Self.list(exitKeys)) or clicking anywhere")
                                + " turns it off. Watch the bar at the bottom disappear.",
                            target: .mode, caps: Array(exitKeys.prefix(1))))
            finalRows.insert((Self.caps(enter, long: false), "Enter \(mode.lowercased()) mode"), at: 0)
            if let first = exitKeys.first { finalRows.append(([first], "Leave \(mode.lowercased()) mode")) }
        }
        if let global, let desk {
            out.append(Step(id: .global, kicker: "Global shortcut", title: "Switch from anywhere",
                            text: "\(Self.modWords(global.mods)) with a number switches workspaces without entering the mode. Go back to workspace \(desk).",
                            target: .bar, caps: Self.caps(global, long: true)))
            finalRows.append((Self.modLabels(global.mods, long: false) + ["1–0"], "Switch from anywhere"))
        }
        out.append(Step(id: .final, kicker: "Done", title: "You're ready to tile",
                        text: "Every shortcut can be changed in Settings → Keyboard Shortcuts."
                            + (original.map { " Finish takes you back to workspace \($0)." } ?? ""),
                        button: "Finish"))
        return out
    }

    private var step: Step { steps[min(index, steps.count - 1)] }

    // MARK: Progress

    private func handle(_ e: Event) {
        guard !ended else { return }
        render() // the mode warning follows the mode
        guard !done, index < steps.count, satisfied(step.id, e) else { return }
        done = true
        flash()
        switch step.id {
        case .focus: tick(0)
        case .move: tick(1)
        case .visit: tick(2)
        default: break
        }
        render()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.advance() }
    }

    private func satisfied(_ id: ID, _ e: Event) -> Bool {
        switch (id, e) {
        case (.mode, .mode(let name)): return !name.isEmpty
        case (.exit, .mode(let name)): return name.isEmpty
        case (.focus, .command(let d, _, _)) where ["movefocus", "cyclenext"].contains(d):
            counter += 1
            flash()
            return counter >= 2
        case (.move, .command(let d, let a, _)):
            return ["swapwindow", "swapnext"].contains(d) || (d == "movewindow" && !a.lowercased().hasPrefix("mon:"))
                || (d == "layoutmsg" && a.lowercased().hasPrefix("swap"))
        case (.layout, .command(let d, _, _)) where ["cyclelayout", "layout", "setlayout"].contains(d):
            counter += 1
            flash()
            return counter >= 2
        case (.visit, .command("workspace", _, _)): return wm.currentWorkspace == other
        case (.back, .command("workspace", _, _)): return wm.currentWorkspace == desk
        case (.send, .command(let d, _, _)): return d.hasPrefix("movetoworkspace")
        case (.global, .command("workspace", _, let inMode)): return !inMode && wm.currentWorkspace == desk
        default: return false
        }
    }

    /// Clicking the keycaps runs the step for you.
    private func simulate() {
        guard !done, index < steps.count else { return }
        let s = step
        flash()
        let run = { [weak self] in
            guard let self, !ended else { return }
            switch s.id {
            case .mode: Hotkeys.shared.setSubmap(mode)
            case .exit: Hotkeys.shared.setSubmap("")
            case .focus: wm.dispatch("cyclenext", "")
            case .move: wm.dispatch("swapnext", "")
            case .layout: wm.dispatch("cyclelayout", "next")
            case .visit: if let other { wm.dispatch("workspace", other) }
            case .back: if let desk { wm.dispatch("workspace", desk) }
            case .send: if let sendTo { wm.dispatch("movetoworkspace", sendTo) }
            case .global:
                Hotkeys.shared.setSubmap("")
                DispatchQueue.main.async { if let desk = self.desk { self.wm.dispatch("workspace", desk) } }
            case .intro, .final: break
            }
        }
        if s.needsMode && Hotkeys.shared.submap.isEmpty {
            Hotkeys.shared.setSubmap(mode)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: run) // let the mode bar show first
        } else {
            run()
        }
    }

    private func flash() {
        model.pressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in self?.model.pressed = false }
    }

    private func tick(_ item: Int) {
        checklist.insert(item)
        PracticeDesk.postProgress(checklist)
    }

    private func advance() {
        guard !ended else { return }
        if index + 1 >= steps.count { return end() }
        index += 1
        done = false
        counter = 0
        render()
    }

    func end() {
        guard !ended else { return }
        ended = true
        follow?.invalidate()
        wm.onDispatch = nil
        wm.onModeChange = nil
        statusButton?.highlight(false)
        Hotkeys.shared.setSubmap("")
        if let panel {
            animate(0.25, changes: { panel.animator().alphaValue = 0 }) { panel.orderOut(nil) }
        }
        if helper?.isRunning == true { helper?.terminate() }
        // Give the practice windows a moment to go, then bring the user's own workspace back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            wm.practice = nil
            if let original, wm.config.virtualWorkspaces { wm.showWorkspace(original) }
            onEnd()
        }
    }

    // MARK: Card

    private func render() {
        guard index < steps.count else { return }
        let s = step
        model.kicker = s.kicker
        model.title = s.title
        model.text = s.text
        model.caps = s.caps
        model.hint = "Press the keys, or click them."
        model.done = done
        model.button = s.button
        model.final = s.id == .final
        model.canSkip = s.id != .final
        model.rows = s.id == .final ? finalRows : []
        let lastIndex = Double(max(1, steps.count - 1))
        model.progress = min(1, (Double(index) + (done ? 1 : 0)) / lastIndex)
        let modeOff = Hotkeys.shared.submap.isEmpty
        model.warning = s.needsMode && modeOff && !done
            ? "\(mode.capitalized) mode is off. Press \(Self.list(steps.first { $0.id == .mode }?.caps ?? [])) to turn it back on."
            : nil
        statusButton?.highlight(s.target == .bar)
    }

    private func reposition(animated: Bool) {
        guard let panel, !ended else { return }
        let size = host.fittingSize
        // The card sits inside the panel with room for its caret and shadow (see CoachCardView).
        let inset = (left: CGFloat(24), top: CGFloat(10))
        let card = NSSize(width: CoachCardView.width, height: size.height - 40)
        let v = screen.visibleFrame
        var o = NSPoint(x: v.midX - card.width / 2, y: v.midY - card.height / 2) // card's bottom-left
        var caret = CoachModel.Caret.none
        switch step.target {
        case .center: break
        case .window:
            if let f = focusedPracticeFrame() { o = NSPoint(x: f.midX - card.width / 2, y: f.midY - card.height / 2) }
        case .bar:
            if let b = statusButton?.window?.frame {
                o.x = min(max(b.midX - card.width + 60, v.minX + 16), v.maxX - card.width - 16)
                o.y = b.minY - 10 - card.height
                caret = .up(min(max(b.midX - o.x, 20), card.width - 20))
            }
        case .mode:
            o = NSPoint(x: v.midX - card.width / 2, y: v.minY + 18 + 28 + 16)
            caret = .down
        }
        o.x = min(max(o.x, v.minX + 16), v.maxX - card.width - 16)
        o.y = min(max(o.y, v.minY + 16), v.maxY - card.height - 16)
        if model.caret != caret { model.caret = caret }
        let frame = NSRect(x: o.x - inset.left, y: o.y - (size.height - inset.top - card.height), width: size.width, height: size.height).integral
        guard frame != target else { return }
        let moved = abs(frame.minX - target.minX) > 1 || abs(frame.maxY - target.maxY) > 1
        target = frame
        if animated && moved && panel.isVisible {
            animate(0.45) { panel.animator().setFrame(frame, display: true) }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: Keycap labels

    private static func same(_ a: String, _ b: String) -> Bool {
        if let x = Direction(a), let y = Direction(b) { return x == y }
        let la = a.lowercased(), lb = b.lowercased()
        return la == lb || (lb == "prev" && la.hasPrefix("prev"))
    }

    private static func caps(_ b: KeyBinding, long: Bool) -> [String] {
        modLabels(b.mods, long: long) + [keyLabel(b.keyCode, long: long)]
    }

    private static func modLabels(_ f: CGEventFlags, long: Bool) -> [String] {
        var out: [String] = []
        if f.contains(.maskControl) { out.append(long ? "⌃ control" : "⌃") }
        if f.contains(.maskAlternate) { out.append(long ? "⌥ option" : "⌥") }
        if f.contains(.maskShift) { out.append(long ? "⇧ shift" : "⇧") }
        if f.contains(.maskCommand) { out.append("⌘") }
        return out
    }

    private static func modWords(_ f: CGEventFlags) -> String {
        var out: [String] = []
        if f.contains(.maskControl) { out.append("Control") }
        if f.contains(.maskAlternate) { out.append("Option") }
        if f.contains(.maskShift) { out.append("Shift") }
        if f.contains(.maskCommand) { out.append("Command") }
        return out.isEmpty ? "A key" : out.joined(separator: "-")
    }

    private static func keyLabel(_ code: UInt16, long: Bool) -> String {
        switch code {
        case 57: return long ? "⇪ caps lock" : "⇪"
        case 53: return "esc"
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "space"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return ConfigDocument.keyName(for: code)?.uppercased() ?? "?"
        }
    }

    /// "H, J, K and L"
    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
