// Settings: the saved-config selector, editor sheets, icon picker and color picker.
import AppKit
import SwiftUI

// MARK: - Glyphs

/// A config's icon: the Ouch logo for built-ins, otherwise its symbol (or a generic one).
struct ConfigGlyph: View {
    let config: SavedConfig
    var size: CGFloat = 16
    var tint: Color = Theme.ink

    var body: some View {
        if config.isBuiltIn {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: size * 1.7, height: size * 1.7)
        } else {
            Image(systemName: config.symbol ?? config.kind.genericSymbol)
                .font(Theme.symbol(size * 0.92, .semibold))
                .foregroundStyle(tint)
                .frame(width: size * 1.7, height: size * 1.7)
        }
    }
}

/// Text and icon colors that stay readable on a config's background.
private func configInk(for config: SavedConfig) -> Color {
    guard let hex = config.colorHex else { return Theme.ink }
    return ConfigLibrary.prefersDarkText(hex: hex) ? Color.black.opacity(0.85) : .white
}

private func configFill(for config: SavedConfig) -> Color? {
    config.colorHex.flatMap { ConfigLibrary.color(hex: $0) }
}

// MARK: - Selector

/// Popover state lives in an object instead of @State (the Command Line Tools ship without SwiftUI's macro plugin).
final class PopoverFlag: ObservableObject { @Published var open = false }

/// The pill that names the active config and opens the list of configs. Only this pill and the rows
/// in its list take the configs' own colours.
struct ConfigSelector: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary
    var width: CGFloat? = nil
    @StateObject private var pop = PopoverFlag()
    @StateObject private var hover = Flag()

    var body: some View {
        let c = library.current(kind)
        let fg = configInk(for: c)
        Button { pop.open.toggle() } label: {
            HStack(spacing: 6) {
                ConfigGlyph(config: c, size: 13, tint: fg)
                Text(c.name).font(Theme.body(13, .medium)).oneLine().foregroundStyle(fg)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.xs, .semibold)).foregroundStyle(fg.opacity(0.7))
            }
            .padding(.leading, 6).padding(.trailing, 12).frame(width: width, height: Theme.controlHeight)
            .background(Capsule().fill(configFill(for: c) ?? (hover.on ? Theme.wellHover : Theme.well)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale(scale: 0.96))
        .onHover { hover.on = $0 }
        .accessibilityLabel("\(kind.title) config: \(c.name)")
        .oPopover(isPresented: $pop.open) { ConfigList(kind: kind, library: library, dismiss: { pop.open = false }) }
    }
}

private struct ConfigList: View {
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
        .frame(width: Theme.menuWidth - 12) // the Surface adds 6 each side
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

// MARK: - Import / export button

/// One button that holds both Import and Export.
struct ConfigTransferMenu: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary

    var body: some View {
        OMenuButton(style: OButtonStyle(variant: .secondary, iconOnly: true), items: {
            [
                MenuItem(id: "import", label: "Import Config…", symbol: "square.and.arrow.down",
                         action: { library.runImportPanel(only: kind == .full ? nil : kind) }),
                MenuItem(id: "export", label: "Export \(kind == .full ? "Full" : kind.title) Config…", symbol: "square.and.arrow.up",
                         action: { library.sheet = .export(kind: kind) }),
            ]
        }) {
            Image(systemName: "square.and.arrow.up.on.square").font(Theme.symbol())
        }
        .fixedSize()
        .tooltip("Import or export").accessibilityLabel("Import or export \(kind.title.lowercased()) config")
    }
}

// MARK: - Sheets

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

struct ConfigSheetView: View {
    let sheet: ConfigSheet
    @ObservedObject var library: ConfigLibrary
    @StateObject private var model = ConfigEditorModel()

    private var kinds: [ConfigKind] {
        switch sheet {
        case .create(let k, _): [k]
        case .edit(let id): [library.config(id: id)?.kind ?? .keyboard]
        case .export(let k): [k]
        }
    }

    private var title: String {
        switch sheet {
        case .create(let k, _): "New \(k.title.lowercased()) config"
        case .edit: "Edit config"
        case .export(let k): "Export \(k == .full ? "full" : k.title.lowercased()) config"
        }
    }

    private var nameProblem: String? {
        let trimmed = model.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if kinds.contains(where: { library.isReserved(trimmed, kind: $0) }) { return "That name is built in. Pick another." }
        return nil
    }
    private var canConfirm: Bool { !model.name.trimmingCharacters(in: .whitespaces).isEmpty && nameProblem == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).textStyle(.title).oneLine()
            if case .export(let kind) = sheet { exportBody(kind) } else { editorBody }
        }
        .padding(24).frame(width: 400)
        .foregroundStyle(Theme.ink)
        .background(Theme.surfaceRaised)
        .onAppear(perform: setUp)
    }

    // Name, with the icon to its left and the color dot to its right.
    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { model.pickingSymbol.toggle() } label: {
                    Image(systemName: model.symbol ?? kinds[0].genericSymbol).font(Theme.symbol(Theme.Icon.lg))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 34, height: Theme.controlHeight)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.well))
                }
                .buttonStyle(.plain).tooltip("Icon").accessibilityLabel("Choose icon")
                .oPopover(isPresented: $model.pickingSymbol) { SymbolGrid(selection: $model.symbol, close: { model.pickingSymbol = false }) }

                OTextField(placeholder: "Name", text: $model.name) { if canConfirm { confirm() } }

                Button { model.pickingColor.toggle() } label: {
                    Circle().fill(model.hasColor ? model.color.color : Color.clear).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(model.hasColor ? Theme.hairline : Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: model.hasColor ? [] : [3, 2])))
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).tooltip("Color").accessibilityLabel("Choose color")
                .oPopover(isPresented: $model.pickingColor) { ColorPopover(model: model) }
            }
            if let p = nameProblem { OStatus(kind: .danger, text: p) }
            HStack(spacing: 8) {
                Spacer()
                OButton("Cancel", variant: .ghost) { cancel() }.keyboardShortcut(.cancelAction)
                OButton(confirmTitle, variant: .primary, shortcut: ["↩"]) { confirm() }.keyboardShortcut(.defaultAction).disabled(!canConfirm)
            }
            .padding(.top, 8)
        }
    }

    private var confirmTitle: String {
        switch sheet { case .edit: "Save"; default: "Create" }
    }

    private func exportBody(_ kind: ConfigKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ORow("Config", description: kind == .full ? "With its keyboard and animation" : nil) {
                OMenuPicker(title: "Config", options: library.configs(kind).map { ($0.id, $0.name + (library.isActive($0) ? " (active)" : "")) },
                            selection: $model.exportID)
            }
            HStack(spacing: 8) {
                Spacer()
                OButton("Cancel", variant: .ghost) { library.sheet = nil }.keyboardShortcut(.cancelAction)
                OButton("Export…", variant: .primary, shortcut: ["↩"]) {
                    library.sheet = nil
                    if let c = library.config(id: model.exportID) { DispatchQueue.main.async { library.runExportPanel(for: c) } }
                }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func setUp() {
        switch sheet {
        case .edit(let id):
            guard let c = library.config(id: id) else { return }
            model.name = c.name
            model.symbol = c.symbol
            model.set(color: c.colorHex.flatMap(HSBA.init(hex:)))
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

// MARK: - Icon picker

private let curatedSymbols: [String] = [
    "star.fill", "bolt.fill", "flame.fill", "leaf.fill", "heart.fill", "moon.fill", "sun.max.fill", "cloud.fill", "drop.fill",
    "snowflake", "sparkles", "wand.and.stars", "paintbrush.fill", "paintpalette.fill", "bucket.fill", "gamecontroller.fill",
    "keyboard", "command", "option", "control", "laptopcomputer", "desktopcomputer", "display", "macwindow",
    "square.grid.2x2.fill", "rectangle.split.3x1.fill", "sidebar.left", "slider.horizontal.3", "gearshape.fill", "wrench.fill",
    "hammer.fill", "briefcase.fill", "book.fill", "graduationcap.fill", "pencil", "terminal.fill",
    "chevron.left.forwardslash.chevron.right", "cpu.fill", "hare.fill", "tortoise.fill", "airplane", "car.fill", "bicycle",
    "figure.run", "music.note", "headphones", "film.fill", "camera.fill", "photo.fill", "theatermasks.fill", "crown.fill",
    "trophy.fill", "flag.fill", "bell.fill", "bookmark.fill", "tag.fill", "pin.fill", "lock.fill", "key.fill", "globe",
    "map.fill", "cube.fill", "shippingbox.fill", "puzzlepiece.fill", "lightbulb.fill", "atom", "pawprint.fill", "tree.fill",
    "mountain.2.fill", "wind", "rainbow", "party.popper.fill",
].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

private struct SymbolGrid: View {
    @Binding var selection: String?
    let close: () -> Void
    private final class Query: ObservableObject { @Published var text = "" }
    @StateObject private var query = Query()

    private var shown: [String] {
        query.text.isEmpty ? curatedSymbols : curatedSymbols.filter { $0.localizedCaseInsensitiveContains(query.text) }
    }

    var body: some View {
        VStack(spacing: 8) {
            OTextField(placeholder: "Search icons", text: $query.text)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 7), spacing: 4) {
                    ForEach(shown, id: \.self) { s in
                        Button { selection = s; close() } label: {
                            Image(systemName: s).font(Theme.symbol(Theme.Icon.lg)).frame(width: 34, height: 34)
                                .foregroundStyle(selection == s ? Theme.onAccent : Theme.ink)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(selection == s ? Theme.accent : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).tooltip(s).accessibilityLabel(s)
                    }
                }
            }
            .frame(height: 190)
            if shown.isEmpty { Text("No icons match").font(Theme.body(12.5)).foregroundStyle(Theme.inkMuted) }
            OButton("Use the default icon", variant: .ghost, size: .sm) { selection = nil; close() }
        }
        .padding(12).frame(width: 300)
    }
}

// MARK: - Color picker

/// Hue, saturation, brightness and opacity: what the picker edits.
struct HSBA: Equatable {
    var h = 0.12, s = 0.8, b = 1.0, a = 1.0

    var color: Color { Color(hue: h, saturation: s, brightness: b, opacity: a) }
    private var ns: NSColor { NSColor(hue: h, saturation: s, brightness: b, alpha: a).usingColorSpace(.sRGB) ?? .black }
    private var bytes: (Int, Int, Int, Int) {
        let c = ns
        func v(_ x: CGFloat) -> Int { Int((x * 255).rounded()) }
        return (v(c.redComponent), v(c.greenComponent), v(c.blueComponent), v(c.alphaComponent))
    }
    var hexRGB: String { let (r, g, b, _) = bytes; return String(format: "#%02X%02X%02X", r, g, b) }
    /// Storage form, RRGGBBAA.
    var hex: String { let (r, g, b, a) = bytes; return String(format: "%02X%02X%02X%02X", r, g, b, a) }

    init() {}
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        let c = NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, al: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &al)
        self.h = Double(h); self.s = Double(s); self.b = Double(v); self.a = Double(al)
    }

    /// RRGGBB or RRGGBBAA.
    init?(hex: String) {
        let t = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard t.count == 6 || t.count == 8, let v = UInt64(t, radix: 16) else { return nil }
        let alpha = t.count == 8
        self.init(r: Double((v >> (alpha ? 24 : 16)) & 0xFF) / 255, g: Double((v >> (alpha ? 16 : 8)) & 0xFF) / 255,
                  b: Double((v >> (alpha ? 8 : 0)) & 0xFF) / 255, a: alpha ? Double(v & 0xFF) / 255 : 1)
    }

    /// What people type: "#E8460C", "E8460C", "rgb(232, 70, 12)" or "hsl(16, 90%, 48%)".
    init?(text: String) {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        // "-" is kept so hsl(-30, …) is hue 330; other negative numbers clamp to 0.
        let signed = t.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Double($0) }
        let nums = signed.map { max($0, 0) }
        if t.hasPrefix("rgb"), nums.count >= 3 {
            self.init(r: min(nums[0], 255) / 255, g: min(nums[1], 255) / 255, b: min(nums[2], 255) / 255, a: nums.count > 3 ? min(nums[3], 1) : 1)
        } else if t.hasPrefix("hsl"), nums.count >= 3 {
            let h = (signed[0].truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360, s = min(nums[1], 100) / 100, l = min(nums[2], 100) / 100
            let v = l + s * min(l, 1 - l)
            self.init()
            self.h = h; self.s = v == 0 ? 0 : 2 * (1 - l / v); self.b = v; self.a = nums.count > 3 ? min(nums[3], 1) : 1
        } else if let c = HSBA(hex: t) {
            self = c
        } else {
            return nil
        }
    }
}

private struct ColorPopover: View {
    @ObservedObject var model: ConfigEditorModel

    var body: some View {
        VStack(spacing: 12) {
            ShadeSquare(color: Binding(get: { model.color }, set: { model.color = $0; model.hasColor = true; model.colorText = $0.hexRGB }))
                .frame(height: 140)
            GradientSlider(value: Binding(get: { model.color.h }, set: { update { $0.h = $1 }($0) }),
                           colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) },
                           knob: Color(hue: model.color.h, saturation: 1, brightness: 1))
            GradientSlider(value: Binding(get: { model.color.a }, set: { update { $0.a = $1 }($0) }),
                           colors: [model.color.color.opacity(0), Color(hue: model.color.h, saturation: model.color.s, brightness: model.color.b)],
                           knob: model.color.color, checker: true)
            HStack(spacing: 8) {
                OTextField(placeholder: "#RRGGBB, rgb() or hsl()", text: $model.colorText, mono: true, onSubmit: applyText)
                OButton("None", variant: .ghost, size: .sm) { model.set(color: nil); model.colorText = "" }.tooltip("No background color")
            }
        }
        .padding(14).frame(width: 260)
    }

    private func update(_ change: @escaping (inout HSBA, Double) -> Void) -> (Double) -> Void {
        { v in
            var c = model.color
            change(&c, v)
            model.color = c
            model.hasColor = true
            model.colorText = c.hexRGB
        }
    }

    private func applyText() {
        guard let c = HSBA(text: model.colorText) else { NSSound.beep(); return }
        model.set(color: c)
    }
}

private struct ShadeSquare: View {
    @Binding var color: HSBA

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.white, Color(hue: color.h, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                OKnob(color: Color(hue: color.h, saturation: color.s, brightness: color.b), size: 18)
                    .position(x: color.s * geo.size.width, y: (1 - color.b) * geo.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                var c = color
                c.s = min(max(v.location.x / geo.size.width, 0), 1)
                c.b = 1 - min(max(v.location.y / geo.size.height, 0), 1)
                color = c
            })
        }
        .accessibilityLabel("Color shade")
    }
}

private struct GradientSlider: View {
    @Binding var value: Double
    let colors: [Color]
    let knob: Color
    var checker = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if checker { Canvas { ctx, size in
                    let s: CGFloat = 6
                    for x in 0..<Int(size.width / s) + 1 { for y in 0..<Int(size.height / s) + 1 where (x + y) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)), with: .color(.gray.opacity(0.3)))
                    } }
                }.clipShape(Capsule()) }
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                OKnob(color: knob, size: 18).offset(x: value * (geo.size.width - 18))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in value = min(max((v.location.x - 9) / (geo.size.width - 18), 0), 1) })
        }
        .frame(height: 18)
    }
}
