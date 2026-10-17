import AppKit
import SwiftUI

extension Coach {
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
        host = OuchHostingView(rootView: CoachCardView(model: model))
        panel = OuchPanel(role: .overlay(.floating, clickThrough: false))
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

    func launchHelper() {
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

    func onScreen(_ w: AXUIElement) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let f = w.frame
        guard !f.isNull else { return nil }
        let r = NSRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        let seen = screen.frame.intersection(r)
        return seen.width * seen.height > 40_000 ? r : nil
    }

    func enter() {
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

    func handle(_ e: Event) {
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

    func revealHint() {
        guard !ended, model.hidden else { return }
        withAnimation(Motion.easeOut) { model.hidden = false }
    }

    func simulate() {
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

}
