import AppKit
import SwiftUI

struct ConfigList: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(library.configs(kind)) { config in row(config) }
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 2)
            OMenuRow {
                dismiss()
                library.sheet = .create(kind: kind, baseID: library.current(kind).id)
            } lead: {
                Image(systemName: "plus").font(Theme.symbol(Theme.Icon.small, .semibold))
                    .foregroundStyle(Theme.inkMuted)
            } label: {
                Text("New config from “\(library.current(kind).name)”").oneLine()
            }
        }
        .frame(width: Theme.menuWidth - 12)
        .foregroundStyle(Theme.ink)
    }

    private func row(_ config: SavedConfig) -> some View {
        let ink = configInk(for: config), removal = config.isBuiltIn ? "reset" : "delete"
        return HStack(spacing: 4) {
            Button { library.select(config); dismiss() } label: {
                HStack(spacing: 8) {
                    ConfigGlyph(config: config, size: 14, tint: ink)
                    Text(config.name).font(Theme.body(13.5, library.isActive(config) ? .medium : .regular)).oneLine()
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                    if library.isActive(config) {
                        Image(systemName: "checkmark").font(Theme.symbol(Theme.Icon.small, .bold))
                            .foregroundStyle(configFill(for: config) == nil ? Theme.accentInk : ink)
                    }
                }
                .padding(.horizontal, 8).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(configFill(for: config) ?? (library.isActive(config) ? Theme.accentSoft : .clear)))
            }
            .buttonStyle(OMenuRowStyle(bare: true))
            OMenuButton(style: OButtonStyle(variant: .ghost, size: .small, iconOnly: true), items: {
                [
                    MenuItem(id: "edit", label: "Edit Name, Icon and Color…", symbol: "pencil",
                             action: { dismiss(); library.sheet = .edit(id: config.id) }),
                    MenuItem(id: "duplicate", label: "Duplicate", symbol: "plus.square.on.square",
                             action: { library.duplicate(config) }),
                    .sep("s"),
                    config.isBuiltIn
                        ? MenuItem(id: "reset", label: "Reset to Default…", symbol: "arrow.counterclockwise",
                                   enabled: library.isEdited(config), action: { confirmReset(config) })
                        : MenuItem(id: "delete", label: "Delete…", symbol: "trash", danger: true,
                                   action: { confirmDelete(config) })
                ]
            }, label: {
                Image(systemName: "ellipsis").font(Theme.symbol())
            })
            .tooltip("Edit, duplicate or \(removal) “\(config.name)”")
            .accessibilityLabel("Edit, duplicate or \(removal) \(config.name)")
        }
    }

    private func confirmReset(_ config: SavedConfig) {
        dismiss()
        DispatchQueue.main.async {
            if ConfigLibrary.confirm("Reset “\(config.name)” to its default?", "Your changes to it can't be restored.",
                                     yes: "Reset", no: "Cancel") {
                library.reset(config)
            }
        }
    }

    private func confirmDelete(_ config: SavedConfig) {
        dismiss()
        DispatchQueue.main.async {
            if ConfigLibrary.confirm("Delete “\(config.name)”?", "This can't be undone.", yes: "Delete", no: "Cancel") {
                library.delete(config)
            }
        }
    }
}
