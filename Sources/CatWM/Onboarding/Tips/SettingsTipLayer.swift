import AppKit
import SwiftUI

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
