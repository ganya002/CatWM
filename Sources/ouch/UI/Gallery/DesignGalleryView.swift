#if DEBUG

import AppKit
import SwiftUI

struct DesignGalleryView: View {

    let setAppearance: (NSAppearance?) -> Void
    @StateObject var m = GalleryModel()

    private static let templateScreenshot: Data? = {
        let sample = HStack(spacing: Theme.Space.sm) {
            DemoWindow(app: DemoApp.all[4], main: true)
            VStack(spacing: Theme.Space.sm) {
                DemoWindow(app: DemoApp.all[1])
                DemoWindow(app: DemoApp.all[2])
            }
        }
        .padding(Theme.Space.sm).frame(width: 560, height: 320).background(Theme.wash)
        return ImageRenderer(content: sample).nsImage?.tiffRepresentation
    }()

    var header: some View {
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

    var colours: some View {
        block("Colour (hex: light / dark)") {
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

    var type: some View {
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

    var radii: [(String, CGFloat)] {
        [("xs", Theme.Radius.xs), ("sm", Theme.Radius.sm), ("md", Theme.Radius.md), ("lg", Theme.Radius.lg),
         ("xl", Theme.Radius.xl), ("pane", Theme.Radius.pane), ("hud", Theme.Radius.hud), ("xxl", Theme.Radius.xxl)]
    }

    var spaces: [(String, CGFloat)] {
        [("xxs", Theme.Space.xxs), ("xs", Theme.Space.xs), ("sm", Theme.Space.sm), ("md", Theme.Space.md),
         ("lg", Theme.Space.lg), ("xl", Theme.Space.xl), ("xxl", Theme.Space.xxl), ("page", Theme.Space.page)]
    }

    var rows: some View {
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
            OGroup("Workspace templates") {
                TemplateRow(name: "Writing", summary: "3 windows · 1 display",
                            screenshot: Self.templateScreenshot,
                            open: {}, rename: {}, update: {}, delete: {})
                TemplateRow(name: "Research", summary: "6 windows · 2 displays", busy: true, open: {}, rename: {}, update: {}, delete: {})
            }
            TemplateSaveRow(name: $m.text, save: {}, cancel: {})
            VStack(spacing: 0) {
                ActionRow(action: QuickAction(id: "template.save.gallery", title: "Save workspace…", symbol: "plus", keys: ["S"]) {},
                          hovered: false, shown: true, index: 0, pick: {}, hover: { _ in })
                ActionRow(action: QuickAction(id: "template.gallery", title: "Writing", symbol: "rectangle.3.group",
                                             keys: ["1"], remove: {}) {},
                          hovered: false, shown: true, index: 1, remove: {}, pick: {}, hover: { _ in })
                ActionRow(action: QuickAction(id: "template.gallery.hover", title: "Research", symbol: "rectangle.3.group",
                                             keys: ["2"], remove: {}) {},
                          hovered: true, shown: true, index: 2, remove: {}, pick: {}, hover: { _ in })
            }
            .frame(width: Theme.submenuWidth)
        }
    }

    var keys: some View {
        block("Keycaps and tooltips") {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                Kbd(keys: ["⌘", "K"])
                Kbd(keys: ["⌥", "⇧", "H"])
                Kbd(keys: ["H", "J", "K", "L"], size: .medium)
                Kbd(keys: ["H"], size: .large)
                Kbd(keys: ["L"], size: .large, pressed: true)
                Kbd(keys: ["H"], size: .medium, onAccent: true)
                    .padding(Theme.Space.sm).background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.accent))
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                OTooltip(text: "Retile", chords: [["Z"]], caret: .none).fixedSize()
                OTooltip(text: "Settings", chords: [["⌘", ","]], caret: .none).fixedSize()
                OTooltip(text: "Swap with main", caret: .none).fixedSize()
                OIconButton(symbol: "gearshape", label: "Hover for a tooltip") {}
            }
        }
    }

    var carets: some View {
        block("Surface carets") {
            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                caretDemo("top(40)", .top(40))
                caretDemo("bottom", .bottom)
                caretDemo("bottomAt(24)", .bottomAt(24))
                caretDemo("leading(20)", .leading(20))
                caretDemo("leadingBottom(24)", .leadingBottom(24))
            }
            .padding(Theme.Space.lg)
        }
    }

    var tiling: some View {
        block("Tiling") {
            WorkspaceStrip(names: (1...9).map(String.init), current: m.workspace, occupied: ["1", "2", "3", "5"]) { m.workspace = $0 }
            LayoutPicker(layouts: Layout.allCases, selection: m.layout, columns: 5) { m.layout = $0 }
                .frame(width: 320)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: Theme.Space.md)], alignment: .leading, spacing: Theme.Space.md) {
                ForEach(Layout.allCases, id: \.self) { l in
                    VStack(spacing: Theme.Space.xs) {
                        LayoutThumbnail(layout: l, selected: l == m.layout).frame(width: 64, height: 40)
                        Text(l.shortTitle).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                    }
                }
            }
        }
    }

    var status: some View {
        block("Status") {
            HStack(spacing: Theme.Space.xl) {
                OStatus(kind: .success, text: "Granted")
                OStatus(kind: .warning, text: "Safari won't shrink further")
                OStatus(kind: .danger, text: "Failed")
                OStatus(kind: .info, text: "Applies to new windows")
            }
        }
    }
    var motion: some View {
        block("Motion") {
            HStack(spacing: Theme.Space.xl) {
                ForEach([("easeOut", Motion.easeOut), ("spring", Motion.spring), ("snap", Motion.snap), ("pop", Motion.pop)], id: \.0) { name, animation in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.well).frame(width: 96, height: 20)
                            Circle().fill(Theme.accent).frame(width: 16, height: 16).offset(x: m.moved ? 78 : 2)
                                .animation(animation, value: m.moved)
                        }
                        Text(name).textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
                OButton("Play") { m.moved.toggle() }
            }
        }
    }
}

#endif
