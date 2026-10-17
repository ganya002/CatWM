#if DEBUG

import AppKit
import SwiftUI

extension DesignGalleryView {
    var moreControls: some View {
        block("More controls") {
            OPageTitle(crumbs: ["Settings", "Layout"], title: "Gaps & padding") {
                OButton("Reset", size: .sm) {}
            }
            .frame(maxWidth: 560)
            GallerySearch(text: $m.search)
            HStack(spacing: Theme.Space.xl) {
                OKnob()
                OKnob(color: Theme.accent)
                OSegmentTrack(title: "Filter") {
                    OSegment(label: "All", count: 12, on: true) {}
                    OSegment(label: "Floating", count: 3, on: false) {}
                    OSegment(label: "Needs review", on: false, hot: true) {}
                }
            }
            HStack(spacing: Theme.Space.xl) {
                RemoveButton(help: "Remove row", variant: .row) {}
                RemoveButton(help: "Close", variant: .close) {}
                RemoveButton(help: "Restore", variant: .restore) {}
                RemoveButton(help: "Remove badge", variant: .badge) {}
                Button {} label: { Text("Press scale").padding(Theme.Space.md).background(Capsule().fill(Theme.well)) }
                    .buttonStyle(PressScale())
            }
            HStack(alignment: .top, spacing: Theme.Space.xs) {
                EssentialTile(title: "Tiling", label: "Tiling", symbol: "rectangle.split.3x1", offSymbol: "rectangle.on.rectangle",
                              isOn: m.essentialOn, shortcut: ["⌥", "T"]) { m.essentialOn.toggle() }
                EssentialTile(title: "Float", label: "Float window", symbol: "macwindow.on.rectangle", offSymbol: "macwindow",
                              isOn: false, shortcut: ["⌥", "F"]) {}
                EssentialTile(title: "Retile", label: "Retile windows", symbol: "arrow.triangle.2.circlepath",
                              shortcut: ["⌥", "Z"], rotates: true) {}
            }
            .frame(width: Theme.menuWidth)
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                OStep(n: 1, text: "Press **H** to focus the window on the left.")
                OStep(n: 2, text: "Press **L** to focus the window on the right.")
            }
        }
    }

    var surfaces: some View {
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
                .frame(width: 420, alignment: .leading)
                .surface(.xl)
            }
            .padding(.top, Theme.Space.md)
        }
    }

    func caretDemo(_ name: String, _ caret: Caret) -> some View {
        Text(name).font(Theme.body(12.5)).foregroundStyle(Theme.ink).frame(width: 124, height: 40).surface(.md, caret: caret)
    }

    var panes: some View {
        block("Pane, wash and glass") {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.wash)
                Text("Content pane on the wash").font(Theme.body()).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface)
                    .pane()
                    .padding(Theme.Space.sm)
            }
            .frame(width: 420, height: 120)
            ZStack {
                LinearGradient(colors: [Theme.accent, Theme.success], startPoint: .leading, endPoint: .trailing)
                Text("Floating glass").font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.xl).padding(.vertical, Theme.Space.md)
                    .floatingGlass(Capsule())
            }
            .frame(width: 420, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            OButton("Open a popover", icon: "rectangle.on.rectangle") { m.popover.toggle() }
                .oPopover(isPresented: $m.popover) {
                    Text("Popover content").font(Theme.body()).foregroundStyle(Theme.ink).padding(Theme.Space.md)
                }
        }
    }

    var menus: some View {
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

}

#endif
