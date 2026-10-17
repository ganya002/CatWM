#if DEBUG
import AppKit
import SwiftUI

final class DesignGallery: NSObject {
    static let shared = DesignGallery()
    private var window: NSWindow?

    func open() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 780),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Ouch Design Gallery"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: DesignGalleryView { [weak w] appearance in
                w?.appearance = appearance
            })
            w.contentMinSize = NSSize(width: 640, height: 480)
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum GalleryAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

private struct ColorToken: Identifiable {
    let name: String
    let path: KeyPath<Palette, Palette.Pair>
    var id: String { name }

    static let all: [ColorToken] = [
        ColorToken(name: "bg", path: \.bg), ColorToken(name: "surface", path: \.surface),
        ColorToken(name: "surfaceRaised", path: \.surfaceRaised), ColorToken(name: "surfaceSunken", path: \.surfaceSunken),
        ColorToken(name: "hover", path: \.hover), ColorToken(name: "hairline", path: \.hairline),
        ColorToken(name: "borderControl", path: \.borderControl),
        ColorToken(name: "ink", path: \.ink), ColorToken(name: "inkMuted", path: \.inkMuted), ColorToken(name: "inkFaint", path: \.inkFaint),
        ColorToken(name: "accent", path: \.accent), ColorToken(name: "accentHover", path: \.accentHover),
        ColorToken(name: "onAccent", path: \.onAccent), ColorToken(name: "accentInk", path: \.accentInk),
        ColorToken(name: "accentSoft", path: \.accentSoft), ColorToken(name: "tint", path: \.tint), ColorToken(name: "focus", path: \.focus),
        ColorToken(name: "success", path: \.success), ColorToken(name: "warning", path: \.warning),
        ColorToken(name: "danger", path: \.danger), ColorToken(name: "dangerSoft", path: \.dangerSoft),
        ColorToken(name: "glass", path: \.glass), ColorToken(name: "wash1", path: \.wash1), ColorToken(name: "wash2", path: \.wash2),
    ]
}

final class GalleryModel: ObservableObject {
    @Published var appearance = GalleryAppearance.system
    @Published var on = true
    @Published var off = false
    @Published var segment = "Spring"
    @Published var gap = 12.0
    @Published var ratio = 50.0
    @Published var speed = 0.64
    @Published var text = ""
    @Published var layout: Layout? = .tall
    @Published var workspace: String? = "2"
}

struct DesignGalleryView: View {
    let setAppearance: (NSAppearance?) -> Void
    @StateObject private var m = GalleryModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                colours
                type
                shape
                buttons
                controls
                rows
                keys
                surfaces
                menus
                tiling
                status
            }
            .padding(Theme.Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .onChange(of: m.appearance) { _, new in setAppearance(new.appearance) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Design Gallery").textStyle(.largeTitle).foregroundStyle(Theme.ink)
                Text("Every token and component, drawn by the real code. Rules: docs/design-system.md").textStyle(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            OSegmented(title: "Appearance", options: GalleryAppearance.allCases.map { ($0, $0.rawValue) },
                       selection: $m.appearance)
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            OSectionHeader(title)
            content()
        }
    }

    private var colours: some View {
        block("Colour") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.md)], alignment: .leading,
                      spacing: Theme.Space.md) {
                ForEach(ColorToken.all) { token in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Color(nsColor: Theme.ns(token.path)))
                            .frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1))
                        Text(token.name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                        Text(hex(token.path)).font(Theme.mono(11, .regular)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }

    private func hex(_ path: KeyPath<Palette, Palette.Pair>) -> String {
        let p = Theme.palette[keyPath: path]
        return String(format: "%06X / %06X", p.light, p.dark)
    }

    private var type: some View {
        block("Type") {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Tile without thinking").font(Theme.display(44))
                Text("Move focus with H J K L").textStyle(.title)
                Text("Gaps & padding").font(Theme.heading())
                Text("Main on the left, the rest stacked on the right").font(Theme.body())
                Text("Applies to new windows only").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                Text("Behavior").textStyle(.sectionTitle).foregroundStyle(Theme.inkMuted)
                Text("Step 2 of 6").kicker()
                Text("bind = $mod, H, movefocus, l").font(Theme.mono(12, .regular))
            }
            .foregroundStyle(Theme.ink)
        }
    }

    private var shape: some View {
        block("Radius, space and elevation") {
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                ForEach(radii, id: \.0) { name, value in
                    VStack(spacing: Theme.Space.xs) {
                        RoundedRectangle(cornerRadius: value, style: .continuous).fill(Theme.tint).frame(width: 56, height: 56)
                        Text(name).font(Theme.body(12, .medium))
                        Text("\(Int(value))").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: Theme.Space.lg) {
                ForEach(spaces, id: \.0) { name, value in
                    VStack(spacing: Theme.Space.xs) {
                        Rectangle().fill(Theme.accent).frame(width: value, height: 14)
                        Text(name).font(Theme.body(12, .medium))
                        Text("\(Int(value))").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            HStack(spacing: Theme.Space.xl) {
                ForEach([("sm", Elevation.sm), ("popover", .popover), ("float", .float)], id: \.0) { name, e in
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    Text(name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                        .frame(width: 110, height: 64)
                        .background(shape.fill(Theme.surfaceRaised))
                        .elevation(e, in: shape)
                }
            }
            .padding(.vertical, Theme.Space.md)
        }
    }

    private var radii: [(String, CGFloat)] {
        [("xs", Theme.Radius.xs), ("sm", Theme.Radius.sm), ("md", Theme.Radius.md), ("lg", Theme.Radius.lg),
         ("xl", Theme.Radius.xl), ("pane", Theme.Radius.pane), ("hud", Theme.Radius.hud), ("xxl", Theme.Radius.xxl)]
    }

    private var spaces: [(String, CGFloat)] {
        [("xxs", Theme.Space.xxs), ("xs", Theme.Space.xs), ("sm", Theme.Space.sm), ("md", Theme.Space.md),
         ("lg", Theme.Space.lg), ("xl", Theme.Space.xl), ("xxl", Theme.Space.xxl), ("page", Theme.Space.page)]
    }

    private var buttons: some View {
        block("Buttons") {
            let variants: [(String, ButtonVariant)] = [("Primary", .primary), ("Secondary", .secondary), ("Ghost", .ghost),
                                                      ("Danger", .danger), ("Ghost danger", .ghostDanger)]
            ForEach([ButtonSize.lg, .regular, .sm], id: \.self) { size in
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.md) {
                        ForEach(variants, id: \.0) { name, variant in
                            OButton(name, variant: variant, size: size) {}
                        }
                    }
                    HStack(spacing: Theme.Space.md) {
                        OButton("With icon", icon: "arrow.triangle.2.circlepath", size: size) {}
                        OButton("Continue", variant: .primary, size: size, shortcut: ["↩"]) {}
                        OButton("Disabled", size: size) {}.disabled(true)
                    }
                }
                .fixedSize()
            }
            HStack(spacing: Theme.Space.md) {
                OIconButton(symbol: "gearshape", label: "Settings") {}
                OIconButton(symbol: "arrow.triangle.2.circlepath", label: "Retile", size: .regular, variant: .secondary) {}
                OIconButton(symbol: "trash", label: "Remove", variant: .ghostDanger) {}
            }
        }
    }

    private var controls: some View {
        block("Controls") {
            HStack(spacing: Theme.Space.xl) {
                OSwitch(isOn: $m.on, label: "Tiling")
                OSwitch(isOn: $m.off, label: "Focus follows mouse")
                OSwitch(isOn: $m.on, label: "Disabled").disabled(true)
                OSegmented(title: "Curve", options: ["Ease", "Spring", "Off"].map { ($0, $0) }, selection: $m.segment)
            }
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                OSlider(value: $m.gap, range: 0...40, step: 1, ticks: [8, 16, 24, 32], resetValue: 12, width: 260,
                        label: "Window gap", format: { "\(Int($0)) px" })
                OSlider(value: $m.ratio, range: 20...80, step: 1, ticks: [50], resetValue: 50, width: 260,
                        label: "Split ratio", format: { "\(Int($0)) / \(100 - Int($0))" })
                OBarSlider(value: $m.speed, range: 0...1, step: 0.01, label: "Speed", symbol: "wand.and.stars",
                           format: { "\(Int($0 * 100))%" })
                    .frame(width: 320)
            }
            HStack(spacing: Theme.Space.lg) {
                OTextField(placeholder: "Text field", text: $m.text)
                    .frame(width: 220)
                OTextField(placeholder: "Monospaced", text: $m.text, mono: true)
                    .frame(width: 220)
            }
        }
    }

    private var rows: some View {
        block("Rows and groups") {
            OGroup("Behavior", footer: "Applies to new windows only.") {
                OSwitchRow("Focus follows mouse", description: "Hovering a window focuses it", isOn: $m.off)
                OSwitchRow("New windows go to main", description: "Instead of the end of the stack", isOn: $m.on)
                ORow("Animation curve", symbol: "wand.and.stars") {
                    OSegmented(title: "Curve", options: ["Ease", "Spring", "Off"].map { ($0, $0) }, selection: $m.segment)
                }
                ORow("Enter window mode", symbol: "keyboard") { Kbd(keys: ["⌘", "⇪"]) }
            }
            .frame(maxWidth: 560)
        }
    }

    private var keys: some View {
        block("Keycaps and tooltips") {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                Kbd(keys: ["⌘", "K"])
                Kbd(keys: ["⌥", "⇧", "H"])
                Kbd(keys: ["H", "J", "K", "L"], size: .medium)
                Kbd(keys: ["H"], size: .large)
                Kbd(keys: ["L"], size: .large, pressed: true)
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                OTooltip(text: "Retile", chords: [["Z"]], caret: .none).fixedSize()
                OTooltip(text: "Settings", chords: [["⌘", ","]], caret: .none).fixedSize()
                OTooltip(text: "Swap with main", caret: .none).fixedSize()
                OIconButton(symbol: "gearshape", label: "Hover for a tooltip") {}
            }
        }
    }

    private var surfaces: some View {
        block("Surfaces") {
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                Text("Retile").font(Theme.body(12.5)).surface(.xs)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Config reloaded", systemImage: "checkmark.circle.fill").font(Theme.body(13.5, .medium))
                    Text("3 binds changed").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                }
                .surface(.sm)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Tip").kicker()
                    Text("Hold ⌥ and drag anywhere in a window to move it.").font(Theme.body()).frame(width: 220, alignment: .leading)
                }
                .padding(Theme.Space.sm)
                .surface(.md)
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Step 2 of 6").kicker()
                    Text("Move focus").textStyle(.title)
                    Text("Use H J K L to jump between windows.").font(Theme.body()).foregroundStyle(Theme.inkMuted)
                    Kbd(keys: ["H"], size: .large)
                }
                .frame(width: 304, alignment: .leading)
                .surface(.lg, caret: .top(40))
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Welcome").kicker()
                    Text("Tile without thinking").font(Theme.display(34))
                    Text("Ouch arranges your windows as you open them.").font(Theme.body()).foregroundStyle(Theme.inkMuted)
                    OButton("Continue", variant: .primary, size: .lg, shortcut: ["↩"]) {}
                }
                .frame(width: 320, alignment: .leading)
                .surface(.xl)
            }
            .padding(.top, Theme.Space.md)
        }
    }

    private var menus: some View {
        block("Menu rows") {
            VStack(spacing: 0) {
                OMenuRow(action: {}, lead: { Image(systemName: "gearshape") }, label: { Text("Settings…") },
                         trailing: { Text("⌘,").foregroundStyle(Theme.inkMuted) })
                OMenuRow(highlighted: true, action: {}, lead: { Image(systemName: "macwindow") }, label: { Text("Highlighted row") })
                OMenuRow(open: true, action: {}, lead: { Image(systemName: "square.grid.2x2") }, label: { Text("Layout") },
                         trailing: { Image(systemName: "chevron.right").foregroundStyle(Theme.inkMuted) })
                OMenuRow(danger: true, action: {}, lead: { Image(systemName: "power") }, label: { Text("Quit Ouch") })
            }
            .frame(width: Theme.menuWidth)
            .padding(Theme.Space.xs + Theme.Space.xxs)
            .surface(.md)
            HStack(spacing: Theme.Space.md) {
                OMenuPicker(title: "Curve", options: ["Ease", "Spring", "Off"].map { ($0, $0) }, selection: $m.segment)
                OMenuButton(items: {
                    [MenuItem(id: "a", label: "Retile", symbol: "arrow.triangle.2.circlepath", shortcut: ["Z"]),
                     MenuItem(id: "b", kind: .check, label: "Tiling", checked: true),
                     .sep("s"),
                     MenuItem(id: "c", label: "Quit Ouch", danger: true)]
                }) { Text("Open a real menu") }
            }
        }
    }

    private var tiling: some View {
        block("Tiling") {
            WorkspaceStrip(names: (1...9).map(String.init), current: m.workspace, occupied: ["1", "2", "3", "5"]) { m.workspace = $0 }
            LayoutPicker(layouts: Layout.allCases, selection: m.layout, columns: 5) { m.layout = $0 }
                .frame(width: 320)
        }
    }

    private var status: some View {
        block("Status") {
            HStack(spacing: Theme.Space.xl) {
                OStatus(kind: .success, text: "Granted")
                OStatus(kind: .warning, text: "Safari won't shrink further")
                OStatus(kind: .danger, text: "Failed")
                OStatus(kind: .info, text: "Applies to new windows")
            }
        }
    }
}
#endif
