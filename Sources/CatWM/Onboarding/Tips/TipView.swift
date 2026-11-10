import AppKit
import CatWMKit
import SwiftUI

struct TipView: View {
    let tip: Tips.Tip
    var inset = EdgeInsets()
    var caret: Caret = .none
    static var panelInset: EdgeInsets { EdgeInsets(all: Elevation.popover.room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                OIconButton(symbol: "xmark", label: "Close tip") { Tips.shared.dismiss(tip) }.padding(.leading, -4)
                Image(systemName: "lightbulb").font(Theme.symbol(Theme.Icon.large)).foregroundStyle(Theme.accentInk)
                    .breatheEffect().frame(width: 16)
                Text(tip.title).font(Theme.heading()).oneLine()
                Spacer(minLength: 0)
            }
            if let body = tip.body {
                Text(body).font(Theme.body()).foregroundStyle(Theme.inkMuted).lineSpacing(1.5)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            if !tip.chords.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(tip.chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .padding(.top, Theme.Space.small)
            }
            HStack(spacing: 4) {
                OButton("No more tips", variant: .ghost, size: .small) { Tips.shared.noMore() }
                    .padding(.leading, -11)
                Spacer(minLength: 8)
                if let action = tip.action {
                    OButton(action.label, variant: .primary) {
                        Tips.shared.dismiss(tip)
                        action.run()
                    }
                } else {
                    OButton("Got it", variant: .primary) { Tips.shared.dismiss(tip) }
                }
            }
            .padding(.top, 12)
        }
        .frame(width: 276)
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
        .surface(.medium, caret: caret)
        .padding(inset)
        .fixedSize()
        .font(Theme.body())
    }
}

struct SettingsTipLayer: View {
    @ObservedObject var tips = Tips.shared
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { geometry in
            if let tip = tips.settings, case .settings(let id) = tip.place, let anchor = anchors[id] {
                let rect = geometry[anchor]
                if rect.midY < geometry.size.height * 0.6 {
                    TipView(tip: tip, caret: .leading(20))
                        .offset(x: rect.maxX + Theme.Space.medium, y: rect.midY - 20)
                        .transition(.opacity.combined(with: .offset(x: -6)))
                } else {
                    TipView(tip: tip, caret: .leadingBottom(24))
                        .frame(height: rect.midY + 24, alignment: .bottom)
                        .offset(x: rect.maxX + Theme.Space.medium)
                        .transition(.opacity.combined(with: .offset(x: -6)))
                }
            }
        }
    }
}

struct MenuBarTipView: View {
    @ObservedObject var model: MenuBarTipModel
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.popover.room) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.medium) {
            Image(systemName: model.state == .good ? "checkmark.circle.fill" : "lightbulb")
                .font(Theme.symbol(Theme.Icon.large))
                .foregroundStyle(model.state == .good ? Theme.success : Theme.accentInk)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.heading()).oneLine()
                if let detail {
                    Text(detail).textStyle(.caption).lineSpacing(1.5).foregroundStyle(Theme.inkMuted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Theme.Space.medium).padding(.vertical, 8)
        .frame(width: model.state == .good ? nil : 288, alignment: .leading)
        .surface(.medium, caret: model.caret.map { .top($0 - Self.inset.leading) } ?? .none)
        .padding(Self.inset)
        .fixedSize()
    }

    private var title: String {
        switch model.state {
        case .move: "Keep CatWM in reach"
        case .good: "Good spot for CatWM"
        case .hidden: "CatWM is behind the notch"
        }
    }

    private var detail: String? {
        switch model.state {
        case .good: nil
        case .move: "Items on the left hide first. Move CatWM right in Control Center › Edit Controls."
        case .hidden: "Move it right, near the clock, in Control Center › Edit Controls."
        }
    }
}

struct TipAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tipAnchor(_ id: String) -> some View {
        anchorPreference(key: TipAnchorKey.self, value: .bounds) { [id: $0] }
    }
}
