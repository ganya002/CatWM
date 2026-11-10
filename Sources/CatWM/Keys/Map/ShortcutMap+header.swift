import AppKit
import CatWMKit
import SwiftUI

extension ShortcutMap {
    @ViewBuilder var body: some View {
        let all = doc.keyActions(in: model.mode)
        let flags = model.flags
        let layer = all.filter { $0.flags == flags }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.extraLarge) {
                header(all)
                keyboard(layer)
                    .frame(maxWidth: 940)
                    .frame(maxWidth: .infinity)
                    .zIndex(1)
                list(layer)
            }
            .padding(.horizontal, Theme.Space.extraLarge).padding(.top, 22).padding(.bottom, 40)
        }
        .onAppear {
            model.mode = doc.submaps.contains(settings.bindMode) ? settings.bindMode : ""
            model.picked = model.busiest(all: doc.keyActions(in: model.mode))
            model.startWatching()
        }
        .onDisappear { model.stopWatching() }
        .onChange(of: model.mode) { _, mode in
            model.selected = nil
            model.picked = model.busiest(all: doc.keyActions(in: mode))
        }
    }

    func header(_ all: [ConfigDocument.KeyAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Theme.Space.small) {
                Text("Shortcut map").textStyle(.title).foregroundStyle(Theme.ink).oneLine()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.Space.medium)
                if doc.submaps.count > 1 {
                    OSegmented(title: "Shortcut set",
                               options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                               selection: $model.mode)
                }
                OButton("Done", variant: .primary, shortcut: ["⎋"]) { close() }
                    .keyboardShortcut(model.selected == nil ? .cancelAction : nil)
            }
            HStack(spacing: Theme.Space.medium) {
                layers(all)
                Spacer(minLength: 8)
                ViewThatFits(in: .horizontal) {
                    Text("Click or hold ⌃ ⌥ ⇧ ⌘ to change the layer").fixedSize()
                    Text("Click a key to edit").fixedSize()
                    Color.clear.frame(width: 0)
                }
                .textStyle(.caption).foregroundStyle(Theme.inkMuted)
            }
            .padding(.top, Theme.Space.medium)
        }
    }

    func reveal(_ row: BindRow) {
        model.selected = nil
        settings.bindMode = row.submap
        settings.shortcutFilter = ""
        settings.expanded.insert(row.id)
        settings.reveal = row.id
        settings.pane = .shortcuts
        withAnimation(Motion.snap) { settings.showMap = false }
    }

    func close() {
        model.selected = nil
        withAnimation(Motion.snap) { settings.showMap = false }
    }

    func layers(_ all: [ConfigDocument.KeyAction]) -> some View {
        let counts = Dictionary(grouping: all, by: { $0.flags.rawValue }).mapValues(\.count)
        var list = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(6)
            .map { (flags: NSEvent.ModifierFlags(rawValue: $0.key), count: $0.value) }
        if !list.contains(where: { $0.flags == model.flags }) { list.append((model.flags, 0)) }
        return HStack(spacing: 4) {
            ForEach(list, id: \.flags.rawValue) { item in
                let active = item.flags == model.flags
                let name = item.flags.isEmpty ? "None" : ConfigDocument.modifierCaps(item.flags).joined()
                Button {
                    model.held = []
                    model.selected = nil
                    withAnimation(Motion.fade) { model.picked = item.flags }
                } label: {
                    HStack(spacing: Theme.Space.extraSmall) {
                        Text(name).font(Theme.keys(12, .medium))
                        Text("\(item.count)").font(Theme.body(11.5)).monospacedDigit()
                            .foregroundStyle(active ? Theme.background.opacity(0.7) : Theme.inkMuted)
                    }
                    .foregroundStyle(active ? Theme.background : Theme.ink)
                    .padding(.horizontal, Theme.Space.medium).frame(height: 26)
                    .background(Capsule().fill(active ? Theme.ink : Theme.well))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("\(name), \(item.count) shortcuts")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .animation(Motion.fade, value: model.flags.rawValue)
    }

    func keyboard(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let one = KeyHintKeyboard.size(scale: 1)
        let codes = Set(layer.map(\.code))
        var hot = Set(KeyHintKeyboard.keys.filter { !$0.modifier.isEmpty && model.flags.contains($0.modifier) }
            .compactMap(\.code))
        if let id = model.hotRow { hot.formUnion(layer.filter { $0.row.id == id }.map(\.code)) }
        let hints = layer.map { KeyHint($0) }
        let pressed = model.pressed.flatMap { codes.contains($0) ? $0 : nil }
        return GeometryReader { geometry in
            let scale = geometry.size.width / one.width
            ZStack(alignment: .topLeading) {
                KeyHintKeyboard(binds: hints, pressed: pressed, hot: hot, scale: scale)
                    .onKeyTap(tap)
                    .onKeyHover { key, inside in
                        if key.modifier.isEmpty, let code = key.code { model.hover(code, inside) }
                    }
                if let code = model.selected, let key = KeyHintKeyboard.key(for: code) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(Motion.fade) { model.selected = nil } }
                    selection(key, code: code, scale: scale, size: geometry.size, frame: geometry.frame(in: .global))
                }
                if model.selected == nil, let code = model.tip, let key = KeyHintKeyboard.key(for: code) {
                    tooltip(key, layer: layer, scale: scale, width: geometry.size.width)
                }
            }
        }
        .aspectRatio(one.width / one.height, contentMode: .fit)
    }

    func tap(_ key: KeyHintKeyboard.Key) {
        if !key.modifier.isEmpty { model.toggle(key.modifier); return }
        guard let code = key.code else { return }
        model.tip = nil
        model.selected = model.selected == code ? nil : code
    }
}
