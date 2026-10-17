import AppKit
import SwiftUI

struct SettingsTipLayer: View {
    @ObservedObject var tips = Tips.shared
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { g in
            if let tip = tips.settings, case .settings(let id) = tip.place, let a = anchors[id] {
                let r = g[a]
                if r.midY < g.size.height * 0.6 {
                    TipView(tip: tip, caret: .leading(20))
                        .offset(x: r.maxX + 14, y: r.midY - 20)
                        .transition(.opacity.combined(with: .offset(x: -6)))
                } else {
                    TipView(tip: tip, caret: .leadingBottom(24))
                        .frame(height: r.midY + 24, alignment: .bottom)
                        .offset(x: r.maxX + 14)
                        .transition(.opacity.combined(with: .offset(x: -6)))
                }
            }
        }
    }
}
