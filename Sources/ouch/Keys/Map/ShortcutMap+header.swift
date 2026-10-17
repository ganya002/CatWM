import AppKit
import SwiftUI

extension ShortcutMap {
    @ViewBuilder var body: some View {
        let all = doc.keyActions(in: model.mode)
        let flags = model.flags
        let layer = all.filter { $0.flags == flags }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(all)
                VStack(alignment: .leading, spacing: 14) {
                    keyboard(layer).zIndex(1)
                    legend(all)
                }
                .frame(maxWidth: 940)
                .frame(maxWidth: .infinity)
                .zIndex(1)
                list(layer)
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, 22).padding(.bottom, 40)
        }
        .onAppear {
            model.mode = doc.submaps.contains(ui.bindMode) ? ui.bindMode : ""
            model.picked = model.busiest(all: doc.keyActions(in: model.mode))
            model.startWatching()
        }
        .onDisappear { model.stopWatching() }
        .onChange(of: model.mode) { _, m in
            model.selected = nil
            model.picked = model.busiest(all: doc.keyActions(in: m))
        }
    }

    func header(_ all: [ConfigDocument.KeyAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OPageTitle(crumbs: ["Settings", "Shortcuts", "Map"], title: "Shortcut Map") {
                if doc.submaps.count > 1 {
                    OSegmented(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                               selection: $model.mode)
                }
                OButton("Done", variant: .primary, shortcut: ["⎋"]) { close() }
                    .keyboardShortcut(model.selected == nil ? .cancelAction : nil)
            }
            HStack(spacing: 14) {
                modifierToggles
                Spacer(minLength: 8)
                combos(all)
            }
            .padding(.top, 14)
        }
    }

    func reveal(_ row: BindRow) {
        model.selected = nil
        ui.bindMode = row.submap
        ui.shortcutFilter = ""
        ui.expanded.insert(row.id)
        ui.reveal = row.id
        ui.pane = .shortcuts
        withAnimation(Motion.snap) { ui.showMap = false }
    }

    func close() {
        model.selected = nil
        withAnimation(Motion.snap) { ui.showMap = false }
    }

    func combos(_ all: [ConfigDocument.KeyAction]) -> some View {
        let counts = Dictionary(grouping: all, by: { $0.flags.rawValue }).mapValues(\.count)
        let list = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (flags: NSEvent.ModifierFlags(rawValue: $0.key), count: $0.value) }
        return HStack(spacing: 4) {
            if !list.isEmpty {
                Text("In use").textStyle(.caption).foregroundStyle(Theme.inkMuted).padding(.trailing, Theme.Space.xs)
            }
            ForEach(list.prefix(5), id: \.flags.rawValue) { item in
                let on = item.flags == model.flags
                let name = item.flags.isEmpty ? "None" : ConfigDocument.modifierCaps(item.flags).joined()
                Button {
                    model.held = []
                    model.selected = nil
                    withAnimation(Motion.fade) { model.picked = item.flags }
                } label: {
                    HStack(spacing: 5) {
                        Text(name).font(Theme.keys(12, .medium))
                        Text("\(item.count)").font(Theme.body(11.5)).monospacedDigit()
                            .foregroundStyle(on ? Theme.onAccent.opacity(0.8) : Theme.inkMuted)
                    }
                    .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(on ? Theme.accent : Theme.well))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .tooltip("Show \(name == "None" ? "shortcuts without modifiers" : name + " shortcuts")")
                .accessibilityLabel("\(name), \(item.count) shortcuts")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(Motion.fade, value: model.flags.rawValue)
    }

    func keyboard(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let one = KeyHintKeyboard.size(scale: 1)
        let codes = Set(layer.map(\.code))
        var hot = Set(KeyHintKeyboard.keys.filter { !$0.modifier.isEmpty && model.flags.contains($0.modifier) }.compactMap(\.code))
        if let id = model.hotRow { hot.formUnion(layer.filter { $0.row.id == id }.map(\.code)) }
        let hints = layer.map { KeyHint($0) }
        let pressed = model.pressed.flatMap { codes.contains($0) ? $0 : nil }
        return GeometryReader { g in
            let scale = g.size.width / one.width
            ZStack(alignment: .topLeading) {
                KeyHintKeyboard(binds: hints, pressed: pressed, hot: hot, scale: scale)
                    .onKeyTap(tap)
                    .onKeyHover { k, inside in
                        if k.modifier.isEmpty, let code = k.code { model.hover(code, inside) }
                    }
                if let code = model.selected, let k = KeyHintKeyboard.key(for: code) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(Motion.fade) { model.selected = nil } }
                    selection(k, code: code, scale: scale, size: g.size, frame: g.frame(in: .global))
                }
                if model.selected == nil, let code = model.tip, let k = KeyHintKeyboard.key(for: code) {
                    tooltip(k, layer: layer, scale: scale, width: g.size.width)
                }
            }
        }
        .aspectRatio(one.width / one.height, contentMode: .fit)
    }

    func tap(_ k: KeyHintKeyboard.Key) {
        if !k.modifier.isEmpty { model.toggle(k.modifier); return }
        guard let code = k.code else { return }
        model.tip = nil
        model.selected = model.selected == code ? nil : code
    }
}
