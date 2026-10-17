#if DEBUG

import AppKit
import SwiftUI

extension DesignGalleryView {
    @ViewBuilder var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                colours
                type
                shape
                buttons
                controls
                rows
                moreControls
                keys
                surfaces
                carets
                panes
                menus
                tiling
                status
                motion
            }
            .padding(Theme.Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .accessibilityHidden(true)
        .onChange(of: m.appearance) { _, new in setAppearance(new.appearance) }
    }

    func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            OSectionHeader(title)
            content()
        }
    }

    func hex(_ path: KeyPath<Palette, Palette.Pair>) -> String {
        let p = Theme.palette[keyPath: path]
        return String(format: "%06X / %06X", p.light, p.dark)
    }

    var shape: some View {
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
                ForEach([("sm", Elevation.sm), ("knob", .knob), ("popover", .popover), ("float", .float)], id: \.0) { name, e in
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    Text(name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                        .frame(width: 110, height: 64)
                        .background(shape.fill(Theme.surfaceRaised))
                        .elevation(e, in: shape)
                }
            }
            .padding(.vertical, Theme.Space.md)
            HStack(spacing: Theme.Space.xl) {
                ForEach([("well", Theme.well), ("wellHover", Theme.wellHover), ("thumbMain", Theme.thumbMain)], id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(color).frame(width: 80, height: 28)
                        Text(name).font(Theme.body(12.5, .medium)).foregroundStyle(Theme.ink)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: Theme.Space.lg) {
                ForEach([("xs", Theme.Icon.xs), ("sm", Theme.Icon.sm), ("md", Theme.Icon.md), ("lg", Theme.Icon.lg), ("xl", Theme.Icon.xl)],
                        id: \.0) { name, size in
                    VStack(spacing: Theme.Space.xs) {
                        Image(systemName: "gearshape").font(Theme.symbol(size)).foregroundStyle(Theme.ink)
                        Text("icon \(name)").textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }

    var buttons: some View {
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

    var controls: some View {
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

}

#endif
