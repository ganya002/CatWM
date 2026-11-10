import AppKit
import CatWMKit
import SwiftUI

struct ShortcutMap: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settings: SettingsUI
    @StateObject var model = ShortcutMapModel()

    var modeEntry: [String]? {
        guard !model.mode.isEmpty, let action = doc.keyActions(in: "").first(where: {
            $0.row.dispatcher == "submap" && $0.arg.lowercased() == model.mode.lowercased()
        }) else { return nil }
        return ConfigDocument.modifierCaps(action.flags) + [ConfigDocument.capLabel(action.key)]
    }

    struct Entry: Identifiable {
        let row: BindRow
        let codes: [UInt16]
        let group: KeyGroup
        var id: UUID { row.id }
    }
}

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

    struct Modifier {
        let flag: NSEvent.ModifierFlags
        let glyph: String
        let name: String
    }

    static let modifiers: [Modifier] = [
        Modifier(flag: .control, glyph: "⌃", name: "Control"), Modifier(flag: .option, glyph: "⌥", name: "Option"),
        Modifier(flag: .shift, glyph: "⇧", name: "Shift"), Modifier(flag: .command, glyph: "⌘", name: "Command")
    ]

    func busiest(all: [ConfigDocument.KeyAction]) -> NSEvent.ModifierFlags {
        let counts = Dictionary(grouping: all, by: { $0.flags.rawValue }).mapValues(\.count)
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
            .map { NSEvent.ModifierFlags(rawValue: $0.key) } ?? []
    }

    func toggle(_ flag: NSEvent.ModifierFlags) {
        held = []
        selected = nil
        withAnimation(Motion.fade) { picked.formSymmetricDifference(flag) }
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

    private func flash(_ code: UInt16, flags pressedFlags: NSEvent.ModifierFlags, submap: String?) {
        guard pressedFlags == flags, submap.map({ $0 == mode }) ?? true else { return }
        flashTimer?.cancel()
        withAnimation(Motion.fade) { pressed = code }
        let work = DispatchWorkItem { [weak self] in withAnimation(Motion.fadeSlow) { self?.pressed = nil } }
        flashTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private static let watched: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    func startWatching() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(Self.watched)
            if event.type == .keyDown {
                if self.selected == nil, !event.isARepeat { self.flash(event.keyCode, flags: mods, submap: nil) }
            } else if mods != self.held, self.selected == nil {
                withAnimation(Motion.fade) { self.held = mods }
            }
            return event
        }
        fireObserver = NotificationCenter.default.addObserver(
            forName: Hotkeys.didFire, object: nil, queue: .main
        ) { [weak self] note in
            guard let bind = note.userInfo?["bind"] as? KeyBinding else { return }
            let mods = NSEvent.ModifierFlags(rawValue: UInt(bind.mods.rawValue)).intersection(Self.watched)
            self?.flash(bind.keyCode, flags: mods, submap: bind.submap)
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
