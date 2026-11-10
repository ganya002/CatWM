import AppKit
import CatWMKit
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
        windowManager.onDispatch = nil
        windowManager.onModeChange = nil
        Hotkeys.shared.onReturn = nil
        statusButton?.highlight(false)
        HUD.shared.avoid = nil
        MenuBarTip.shared.suppressed = false
        Hotkeys.shared.setSubmap("")
        if KeyHelp.shared.isVisible { KeyHelp.shared.hide() }
        if SortPanel.shared.isOpen { SortPanel.shared.revert() }
        if let panel {
            Motion.group(0.25, changes: { Motion.setAlpha(0, on: panel) }, completion: { panel.orderOut(nil) })
        }
        if helper?.isRunning == true { helper?.terminate() }
        lesson.ended(how, at: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            windowManager.practice = nil
            if let original, windowManager.config.virtualWorkspaces { windowManager.showWorkspace(original) }
            onEnd(how)
        }
    }

    func render() {
        guard let step else { return }
        model.title = step.title
        model.text = step.text
        model.caps = step.caps
        model.capsDone = step.tokens.count == step.caps.count ? step.tokens.map { seen.contains($0) } : []
        model.recall = step.recall
        model.done = done
        model.button = step.button
        model.summary = step.summary
        model.canHead = !step.final
        let lastIndex = Double(max(1, lesson.count - 1))
        model.progress = min(1, (Double(index) + (done ? 1 : 0)) / lastIndex)
        let modeOff = Hotkeys.shared.submap.isEmpty
        let enterKeys = KeyWords.list(book.enterCaps(long: false))
        model.warning = step.needsMode && modeOff && !done && !book.mode.isEmpty
            ? "\(book.mode.capitalized) mode is off. Press \(enterKeys) to turn it back on."
            : nil
        statusButton?.highlight(step.target == .bar)
        MenuBarTip.shared.suppressed = step.target == .bar
    }

    func reposition(animated: Bool) {
        guard let panel, let host, !ended, let step else { return }
        let size = host.fittingSize
        let pad = CoachCardView.inset
        let card = NSSize(width: size.width - pad.leading - pad.trailing, height: size.height - pad.top - pad.bottom)
        let visible = screen.visibleFrame
        var origin = NSPoint(x: visible.midX - card.width / 2, y: visible.midY - card.height / 2)
        var caret = CoachModel.Caret.none
        switch step.target {
        case .center: break
        case .window:
            if let window = focusedPractice, let windowFrame = onScreen(window) {
                origin = NSPoint(x: windowFrame.midX - card.width / 2, y: windowFrame.midY - card.height / 2)
            }
        case .bar:
            if let button = statusButton?.window?.frame {
                origin.x = min(max(button.midX - card.width + 60, visible.minX + 16), visible.maxX - card.width - 16)
                origin.y = button.minY - 10 - card.height
                caret = .pointingUp(min(max(button.midX - origin.x, 20), card.width - 20))
            }
        case .mode:
            origin = NSPoint(x: visible.midX - card.width / 2, y: visible.minY + 48)
        }
        origin.x = min(max(origin.x, visible.minX + 16), visible.maxX - card.width - 16)
        origin.y = min(max(origin.y, visible.minY + 16), visible.maxY - card.height - 16)
        if model.caret != caret { model.caret = caret }
        let frame = NSRect(x: origin.x - pad.leading, y: origin.y - pad.bottom,
                           width: size.width, height: size.height).integral
        HUD.shared.avoid = NSRect(origin: origin, size: card)
        guard frame != target else { return }
        let moved = abs(frame.minX - target.minX) > 1 || abs(frame.maxY - target.maxY) > 1
        target = frame
        if animated && moved && panel.isVisible {
            Motion.group(0.45) { Motion.setFrame(frame, on: panel) }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
