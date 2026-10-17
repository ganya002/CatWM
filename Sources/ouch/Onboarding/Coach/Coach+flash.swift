import AppKit
import SwiftUI

extension Coach {
    func flash() {
        model.pressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in self?.model.pressed = false }
    }

    func returnPressed() -> Bool {
        guard !ended, step?.button != nil, panel?.isVisible == true else { return false }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front == helperPID || front == getpid() else { return false }
        DispatchQueue.main.async { [weak self] in self?.advance() }
        return true
    }

    func advance() {
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

    func render() {
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

    func reposition(animated: Bool) {
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
