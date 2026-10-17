import AppKit
import SwiftUI

final class SettingsUI: ObservableObject {
    @Published var pane: Pane = .general
    @Published var search = ""
    @Published var shortcutFilter = ""
    @Published var bindMode = ""
    @Published var advancedOpen: Set<Pane> = []
    @Published var highlight: String?
    @Published var expanded: Set<UUID> = []
    @Published var reveal: UUID?
    @Published var showMap = false
    @Published var newID = ""
    @Published var previewFlipped = false
    @Published var bezierText = ""
    @Published var linkedPadding = true
    @Published var status = WindowManager.shared.status()
    @Published var recording: UUID? { didSet { updateMonitor() } }

    private let doc: ConfigDocument
    private var monitor: Any?
    private var timer: Timer?

    init(doc: ConfigDocument) { self.doc = doc }

    func beginSession() {
        let c = doc.config
        linkedPadding = Set([c.paddingTop, c.paddingBottom, c.paddingLeft, c.paddingRight]).count == 1
        refreshStatus()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshStatus() }
        timer?.tolerance = 0.2
    }

    func endSession() {
        recording = nil
        showMap = false
        search = ""
        timer?.invalidate()
        timer = nil
    }

    func refreshStatus() { status = WindowManager.shared.status() }

    func open(_ entry: SettingEntry) {
        search = ""
        showMap = false
        if let row = entry.bind {
            bindMode = row.submap
            shortcutFilter = ""
            expanded.insert(row.id)
            reveal = row.id
        }
        if entry.advanced { advancedOpen.insert(entry.pane) }
        pane = entry.pane
        highlight = nil
        DispatchQueue.main.async { self.highlight = entry.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.highlight == entry.id { withAnimation(Motion.fadeAway) { self?.highlight = nil } }
        }
    }

    private func updateMonitor() {
        guard recording != nil else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            Hotkeys.shared.paused = false
            return
        }
        Hotkeys.shared.paused = true
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in guard let self else { return e }; return self.record(e) }
        }
    }

    private func record(_ e: NSEvent) -> NSEvent? {
        if e.type == .flagsChanged && e.keyCode != 57 { return e }
        guard let id = recording, let i = doc.binds.firstIndex(where: { $0.id == id }) else { recording = nil; return e }
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let esc = e.keyCode == 53 && flags.isEmpty
        let isRange = BindRange.isRange(doc.binds[i].key)
        if esc && (doc.binds[i].submap.isEmpty || isRange) {
            recording = nil
            return nil
        }
        guard let name = ConfigDocument.keyName(for: e.keyCode) else { NSSound.beep(); return nil }
        if esc {
            doc.binds[i].key = "escape"; doc.binds[i].mods = ""
        } else if isRange {
            doc.binds[i].mods = doc.modsString(for: flags)
        } else {
            doc.binds[i].key = name
            doc.binds[i].mods = doc.modsString(for: flags)
        }
        recording = nil
        return nil
    }
}
