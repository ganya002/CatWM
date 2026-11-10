import AppKit
import CatWMKit
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
            } label: {
                Text("New config from “\(library.current(kind).name)”").oneLine()
            } trailing: {}
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
                            .foregroundStyle(configFill(for: config) == nil ? Theme.ink : ink)
                    }
                }
                .padding(.horizontal, 8).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(configFill(for: config) ?? (library.isActive(config) ? Theme.hover : .clear)))
            }
            .buttonStyle(OMenuRowStyle(bare: true))
            OMenuButton(style: OButtonStyle(variant: .ghost, size: .small, iconOnly: true), items: {
                [
                    MenuItem(id: "edit", label: "Edit name, icon and color…",
                             action: { dismiss(); library.sheet = .edit(id: config.id) }),
                    MenuItem(id: "duplicate", label: "Duplicate",
                             action: { library.duplicate(config) }),
                    .sep("s"),
                    config.isBuiltIn
                        ? MenuItem(id: "reset", kind: .sub, label: "Reset to default…", danger: true,
                                   enabled: library.isEdited(config),
                                   width: Theme.submenuWidth,
                                   children: [MenuItem(id: "reset-confirm", label: "Reset “\(config.name)”",
                                                       danger: true, action: { library.reset(config) })])
                        : MenuItem(id: "delete", kind: .sub, label: "Delete…", danger: true,
                                   width: Theme.submenuWidth,
                                   children: [MenuItem(id: "delete-confirm", label: "Delete “\(config.name)”",
                                                       danger: true, action: { library.delete(config) })])
                ]
            }, label: {
                Image(systemName: "ellipsis").font(Theme.symbol())
            })
            .tooltip("More actions")
            .accessibilityLabel("Edit, duplicate or \(removal) \(config.name)")
        }
    }
}

struct ConfigTransferMenu: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary

    var body: some View {
        OMenuButton(style: OButtonStyle(variant: .secondary, iconOnly: true), items: {
            [
                MenuItem(id: "import", label: "Import config…",
                         action: { library.runImportPanel(only: kind == .full ? nil : kind) }),
                MenuItem(id: "export", label: "Export \(kind == .full ? "full" : kind.title.lowercased()) config…",
                         action: { library.sheet = .export(kind: kind) })
            ]
        }, label: {
            Image(systemName: "square.and.arrow.up.on.square").font(Theme.symbol())
        })
        .fixedSize()
        .tooltip("Import or export").accessibilityLabel("Import or export \(kind.title.lowercased()) config")
    }
}
