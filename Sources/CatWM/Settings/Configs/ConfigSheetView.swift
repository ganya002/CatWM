import AppKit
import CatWMKit
import SwiftUI

struct ConfigSheetView: View {
    let sheet: ConfigSheet
    @ObservedObject var library: ConfigLibrary
    @StateObject private var model = ConfigEditorModel()

    private var kinds: [ConfigKind] {
        switch sheet {
        case .create(let kind, _): [kind]
        case .edit(let id): [library.config(id: id)?.kind ?? .keyboard]
        case .export(let kind): [kind]
        }
    }

    private var title: String {
        switch sheet {
        case .create(let kind, _): "New \(kind.title.lowercased()) config"
        case .edit: "Edit config"
        case .export(let kind): "Export \(kind == .full ? "full" : kind.title.lowercased()) config"
        }
    }

    private var editedID: String? {
        if case .edit(let id) = sheet { id } else { nil }
    }

    private var nameProblem: String? {
        let trimmed = model.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if kinds.contains(where: { library.isReserved(trimmed, kind: $0, ignoring: editedID) }) {
            return "That name is built in. Pick another."
        }
        return nil
    }
    private var canConfirm: Bool { !model.name.trimmingCharacters(in: .whitespaces).isEmpty && nameProblem == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.medium) {
            Text(title).textStyle(.title).oneLine()
            if case .export(let kind) = sheet { exportBody(kind) } else { editorBody }
        }
        .padding(24).frame(width: 400)
        .foregroundStyle(Theme.ink)
        .background(Theme.surfaceRaised)
        .onAppear(perform: setUp)
    }

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { model.pickingSymbol.toggle() } label: {
                    Image(systemName: model.symbol ?? kinds[0].genericSymbol).font(Theme.symbol(Theme.Icon.large))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: Theme.controlHeight)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .fill(Theme.well))
                }
                .buttonStyle(.plain).accessibilityLabel("Choose icon")
                .oPopover(isPresented: $model.pickingSymbol) {
                    SymbolGrid(selection: $model.symbol, close: { model.pickingSymbol = false })
                }

                OTextField(placeholder: "Name", text: $model.name) { if canConfirm { confirm() } }

                Button { model.pickingColor.toggle() } label: {
                    Circle().fill(model.hasColor ? model.color.color : Color.clear).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(
                            model.hasColor ? Theme.hairline : Theme.borderControl,
                            style: StrokeStyle(lineWidth: 1, dash: model.hasColor ? [] : [3, 2])))
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Choose color")
                .oPopover(isPresented: $model.pickingColor) { ColorPopover(model: model) }
            }
            if let problem = nameProblem { OStatus(kind: .danger, text: problem) }
            HStack(spacing: 8) {
                Spacer()
                OButton("Cancel", variant: .ghost) { cancel() }.keyboardShortcut(.cancelAction)
                OButton(confirmTitle, variant: .primary, shortcut: ["↩"]) { confirm() }
                    .keyboardShortcut(.defaultAction).disabled(!canConfirm)
            }
            .padding(.top, 8)
        }
    }

    private var confirmTitle: String {
        switch sheet {
        case .edit: "Save"
        default: "Create"
        }
    }

    private func exportBody(_ kind: ConfigKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ORow("Config", description: kind == .full ? "With its keyboard and animation" : nil) {
                OMenuPicker(title: "Config",
                            options: library.configs(kind).map {
                                ($0.id, $0.name + (library.isActive($0) ? " (active)" : ""))
                            },
                            selection: $model.exportID)
            }
            HStack(spacing: 8) {
                Spacer()
                OButton("Cancel", variant: .ghost) { library.sheet = nil }.keyboardShortcut(.cancelAction)
                OButton("Export…", variant: .primary, shortcut: ["↩"]) {
                    library.sheet = nil
                    if let config = library.config(id: model.exportID) {
                        DispatchQueue.main.async { library.runExportPanel(for: config) }
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func setUp() {
        switch sheet {
        case .edit(let id):
            guard let config = library.config(id: id) else { return }
            model.name = config.name
            model.symbol = config.symbol
            model.set(color: config.colorHex.flatMap(HSBA.init(hex:)))
        case .export(let kind):
            model.exportID = library.current(kind).id
        default:
            break
        }
    }

    private func confirm() {
        switch sheet {
        case .create(let kind, let base):
            library.create(kind: kind, baseID: base, name: model.name, symbol: model.symbol, colorHex: model.colorHex)
        case .edit(let id):
            library.update(id: id, name: model.name, symbol: model.symbol, colorHex: model.colorHex)
        case .export:
            return
        }
        library.sheet = nil
    }

    private func cancel() {
        library.sheet = nil
    }
}

final class ConfigEditorModel: ObservableObject {
    @Published var name = ""
    @Published var symbol: String?
    @Published var hasColor = false
    @Published var color = HSBA()
    @Published var colorText = ""
    @Published var exportID = ""
    @Published var pickingSymbol = false
    @Published var pickingColor = false

    var colorHex: String? { hasColor ? color.hex : nil }
    func set(color new: HSBA?) {
        hasColor = new != nil
        if let new { color = new; colorText = new.hexRGB }
    }
}
