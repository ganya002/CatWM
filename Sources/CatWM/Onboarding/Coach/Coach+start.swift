import AppKit
import CatWMKit
import SwiftUI

extension Coach {
    func start() {
        if windowManager.config.virtualWorkspaces {
            original = windowManager.currentWorkspace
            let used = Set(windowManager.workspaceSummary().all.filter { $0.windows > 0 || $0.shown }.map(\.name))
            let free = (1...10).map(String.init).filter { !used.contains($0) }
            desk = free.first
            other = free.count > 1 ? free[1] : nil
            sendTo = free.count > 2 ? free[2] : nil
        }
        book = BindBook(binds: windowManager.config.bindings)
        lesson.prepare(self)
        index = min(lesson.startIndex, lesson.count - 1)
        if let desk { windowManager.showWorkspace(desk) }
        launchHelper()

        windowManager.onDispatch = { [weak self] dispatcher, argument, inMode in
            self?.handle(.command(dispatcher, argument, inMode: inMode))
        }
        windowManager.onModeChange = { [weak self] name in self?.handle(.mode(name)) }
        Hotkeys.shared.onReturn = { [weak self] in self?.returnPressed() ?? false }

        model.tryKeys = { [weak self] in self?.simulate() }
        model.next = { [weak self] in self?.advance() }
        let ending: Ending = lesson.pausable ? .paused : .skipped
        model.headAction = { [weak self] in self?.end(ending) }
        model.headLabel = lesson.pausable ? "Pause" : "Skip tour"
        model.headSymbol = lesson.pausable ? "pause.fill" : nil
        model.reveal = { [weak self] in self?.revealHint() }
        model.tutorial = { [weak self] in self?.end(.tutorial) }
        let host = CatWMHostingView(rootView: CoachCardView(model: model))
        let panel = CatWMPanel(role: .overlay(.floating, clickThrough: false))
        panel.contentView = host
        self.host = host
        self.panel = panel
        enter()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !ended else { return }
            reposition(animated: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            Motion.group(0.35) { Motion.setAlpha(1, on: panel) }
            follow = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.handle(.tick)
                self?.reposition(animated: true)
            }
        }
    }

    func launchHelper() {
        guard let exe = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = exe
        let apps = PracticeDesk.pickApps()
        process.arguments = ["practice", String(getpid()), apps.map(\.title).joined(separator: ",")]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.end(.skipped) }
        }
        do { try process.run() } catch {
            Log.info("coach: couldn't open practice windows: \(error.localizedDescription)")
            return
        }
        helper = process
        helperPID = process.processIdentifier
        var map: [String: String] = [:]
        if let desk {
            for (i, app) in apps.enumerated() { map[app.title] = i < PracticeDesk.deskCount ? desk : other ?? desk }
        }
        windowManager.practice = (helperPID, map)
        for delay in [0.4, 0.7, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.windowManager.scheduleRefresh()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, !ended, let desk else { return }
            windowManager.showWorkspace(desk)
        }
    }

    func onScreen(_ window: AXUIElement) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let axFrame = window.frame
        guard !axFrame.isNull else { return nil }
        let rect = NSRect(x: axFrame.minX, y: primary.frame.maxY - axFrame.maxY,
                          width: axFrame.width, height: axFrame.height)
        let seen = screen.frame.intersection(rect)
        return seen.width * seen.height > 40_000 ? rect : nil
    }

    func enter() {
        hintWork?.cancel()
        done = false
        hits = 0
        seen = []
        let current = lesson.step(index, in: self)
        step = current
        model.hidden = current.recall
        if current.recall {
            let work = DispatchWorkItem { [weak self] in self?.revealHint() }
            hintWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: work)
        }
        render()
    }

    func handle(_ event: Event) {
        guard !ended, let step else { return }
        if case .tick = event {} else { render() }
        guard !done, let token = step.accept(event) else { return }
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
        guard !done, let step, let run = step.simulate else { return }
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
