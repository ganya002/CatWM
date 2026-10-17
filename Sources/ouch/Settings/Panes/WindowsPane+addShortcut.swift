import AppKit
import SwiftUI

extension WindowsPane {
    func addShortcut(_ spec: CursorShortcutSpec) {
        let row: BindRow
        if let existing = unfinishedShortcut(spec) {
            row = existing
        } else {
            let mode = windowMode
            row = BindRow(mods: mode.isEmpty ? doc.modVarName : "", key: "",
                          dispatcher: spec.dispatcher, args: spec.args, submap: mode)
            doc.binds.append(row)
        }
        ui.open(SettingEntry(id: "bind.\(row.id)", title: spec.title, pane: .shortcuts, bind: row))
        DispatchQueue.main.async { ui.recording = row.id }
    }

    func add() {
        let id = ui.newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !doc.config.floating.contains(id) else { return }
        withAnimation(Motion.easeOut) { doc.config.floating.append(id) }
        ui.newID = ""
    }

    func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    func appURL(_ id: String) -> URL? {
        id.hasSuffix("*") ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    func appName(_ id: String) -> String? {
        appURL(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
    @ViewBuilder func appIcon(_ id: String) -> some View {
        if let url = appURL(id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 26, height: 26).padding(1)
        }
    }
}
