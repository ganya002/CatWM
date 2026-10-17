import AppKit
import SwiftUI

struct ConfigList: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(library.configs(kind)) { c in row(c) }
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 2)
            OMenuRow {
                dismiss()
                library.sheet = .create(kind: kind, baseID: library.current(kind).id)
            } lead: {
                Image(systemName: "plus").font(Theme.symbol(Theme.Icon.sm, .semibold)).foregroundStyle(Theme.inkMuted)
            } label: {
                Text("New config from “\(library.current(kind).name)”").oneLine()
            }
        }
        .frame(width: Theme.menuWidth - 12)
        .foregroundStyle(Theme.ink)
    }

    private func row(_ c: SavedConfig) -> some View {
        let fg = configInk(for: c)
        return HStack(spacing: 4) {
            Button { library.select(c); dismiss() } label: {
                HStack(spacing: 8) {
                    ConfigGlyph(config: c, size: 14, tint: fg)
                    Text(c.name).font(Theme.body(13.5, library.isActive(c) ? .medium : .regular)).oneLine().foregroundStyle(fg)
                    Spacer(minLength: 0)
                    if library.isActive(c) {
                        Image(systemName: "checkmark").font(Theme.symbol(Theme.Icon.sm, .bold))
                            .foregroundStyle(configFill(for: c) == nil ? Theme.accentInk : fg)
                    }
                }
                .padding(.horizontal, 8).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(configFill(for: c) ?? (library.isActive(c) ? Theme.accentSoft : .clear)))
            }
            .buttonStyle(OMenuRowStyle(bare: true))
            if c.isBuiltIn {
                OIconButton(symbol: "plus", label: "New config based on “\(c.name)”") {
                    dismiss(); library.sheet = .create(kind: kind, baseID: c.id)
                }
            } else {
                OMenuButton(style: OButtonStyle(variant: .ghost, size: .sm, iconOnly: true), items: {
                    [
                        MenuItem(id: "edit", label: "Edit Name, Icon and Color…", symbol: "pencil", action: { dismiss(); library.sheet = .edit(id: c.id) }),
                        MenuItem(id: "duplicate", label: "Duplicate", symbol: "plus.square.on.square", action: { library.duplicate(c) }),
                        .sep("s"),
                        MenuItem(id: "delete", label: "Delete…", symbol: "trash", danger: true, action: { confirmDelete(c) }),
                    ]
                }) {
                    Image(systemName: "ellipsis").font(Theme.symbol())
                }
                .tooltip("Edit, duplicate or delete “\(c.name)”")
                .accessibilityLabel("Edit, duplicate or delete \(c.name)")
            }
        }
    }

    private func confirmDelete(_ c: SavedConfig) {
        dismiss()
        DispatchQueue.main.async {
            if ConfigLibrary.confirm("Delete “\(c.name)”?", "This can't be undone.", yes: "Delete", no: "Cancel") { library.delete(c) }
        }
    }
}
