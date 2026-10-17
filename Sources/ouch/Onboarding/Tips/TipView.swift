import AppKit
import SwiftUI

struct TipView: View {
    let tip: Tips.Tip
    var inset = EdgeInsets()
    var caret: Caret = .none
    static let panelInset = EdgeInsets(top: 18, leading: 32, bottom: 44, trailing: 32)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb").font(Theme.symbol(Theme.Icon.lg)).foregroundStyle(Theme.accentInk)
                    .breatheEffect().frame(width: 16)
                Text(tip.title).font(Theme.heading()).oneLine()
                Spacer(minLength: 4)
                OIconButton(symbol: "xmark", label: "Close tip") { Tips.shared.dismiss(tip) }.padding(.trailing, -4)
            }
            if let body = tip.body {
                Text(body).font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).lineSpacing(1.5)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            if !tip.chords.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(tip.chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .padding(.top, 10)
            }
            HStack(spacing: 4) {
                OButton("No more tips", variant: .ghost, size: .sm) { Tips.shared.noMore() }
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
        .surface(.md, caret: caret)
        .padding(inset)
        .fixedSize()
        .font(Theme.body())
    }
}
