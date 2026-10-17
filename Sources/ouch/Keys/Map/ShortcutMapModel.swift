import AppKit
import SwiftUI

final class ShortcutMapModel: ObservableObject {
    @Published var mode = ""
    @Published var picked: NSEvent.ModifierFlags = []
    @Published var held: NSEvent.ModifierFlags = []
    @Published var hovered: UInt16?
    @Published var tip: UInt16?
    @Published var tipWidth: CGFloat = 0
    @Published var editorHeight: CGFloat = 480
    @Published var selected: UInt16? {
        didSet { if selected == nil, oldValue != nil { held = NSEvent.modifierFlags.intersection(Self.watched) } }
    }
    @Published var pressed: UInt16?
    @Published var hotRow: UUID?
    private var monitor: Any?
    private var fireObserver: NSObjectProtocol?
    private var tipTimer: DispatchWorkItem?
    private var flashTimer: DispatchWorkItem?

    var flags: NSEvent.ModifierFlags { held.isEmpty ? picked : held }

    static let modifiers: [(flag: NSEvent.ModifierFlags, glyph: String, name: String)] =
        [(.control, "⌃", "Control"), (.option, "⌥", "Option"), (.shift, "⇧", "Shift"), (.command, "⌘", "Command")]

    func busiest(all: [ConfigDocument.KeyAction]) -> NSEvent.ModifierFlags {
        let counts = Dictionary(grouping: all, by: { $0.flags.rawValue }).mapValues(\.count)
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }.map { NSEvent.ModifierFlags(rawValue: $0.key) } ?? []
    }

    func toggle(_ f: NSEvent.ModifierFlags) {
        held = []
        selected = nil
        withAnimation(Motion.fade) { picked.formSymmetricDifference(f) }
    }

    func hover(_ code: UInt16, _ inside: Bool) {
        tipTimer?.cancel()
        if inside {
            hovered = code
            if tip != nil { tip = code; return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hovered == code else { return }
                withAnimation(Motion.fade) { self.tip = code }
            }
            tipTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + OTooltip.delay, execute: work)
        } else if hovered == code {
            hovered = nil
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hovered == nil else { return }
                withAnimation(Motion.fade) { self.tip = nil }
            }
            tipTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    private func flash(_ code: UInt16, flags f: NSEvent.ModifierFlags, submap: String?) {
        guard f == flags, submap.map({ $0 == mode }) ?? true else { return }
        flashTimer?.cancel()
        withAnimation(Motion.fade) { pressed = code }
        let work = DispatchWorkItem { [weak self] in withAnimation(Motion.fadeSlow) { self?.pressed = nil } }
        flashTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private static let watched: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    func startWatching() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            guard let self else { return e }
            let f = e.modifierFlags.intersection(Self.watched)
            if e.type == .keyDown {
                if self.selected == nil, !e.isARepeat { self.flash(e.keyCode, flags: f, submap: nil) }
            } else if f != self.held, self.selected == nil {
                withAnimation(Motion.fade) { self.held = f }
            }
            return e
        }
        fireObserver = NotificationCenter.default.addObserver(forName: Hotkeys.didFire, object: nil, queue: .main) { [weak self] n in
            guard let b = n.userInfo?["bind"] as? KeyBinding else { return }
            let f = NSEvent.ModifierFlags(rawValue: UInt(b.mods.rawValue)).intersection(Self.watched)
            self?.flash(b.keyCode, flags: f, submap: b.submap)
        }
    }

    func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let fireObserver { NotificationCenter.default.removeObserver(fireObserver) }
        monitor = nil
        fireObserver = nil
        tipTimer?.cancel()
        held = []
        tip = nil
        hovered = nil
    }
}
