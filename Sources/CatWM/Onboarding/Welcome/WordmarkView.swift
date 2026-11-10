import AppKit
import CatWMKit
import SwiftUI

struct WordmarkView: View {
    @ObservedObject var model: WordmarkModel
    let size: CGFloat

    var body: some View {
        VStack(spacing: Theme.Space.medium) {
            HStack(alignment: .center, spacing: size * 0.12) {
                CatMascot(feeling: .content).frame(height: size * 0.92).foregroundStyle(.white)
                Text("CatWM").font(Theme.wordmark(size)).tracking(-size * 0.03).foregroundStyle(.white)
            }
            .legible()
            .squish(on: model.landed, delay: 0.3)
            tagline(max(16, min(22, size / 6)))
                .foregroundStyle(Color.white.opacity(0.92))
                .legible(strong: true)
                .opacity(model.subtitle ? 1 : 0)
                .animation(Motion.introReveal, value: model.subtitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tagline(_ points: CGFloat) -> Text {
        Text("Hyprland").font(Theme.body(points, .medium)).foregroundColor(hyprlandBlue)
            + Text("-style tiling for macOS.").font(Theme.body(points, .light))
    }
}

final class WordmarkModel: ObservableObject {
    @Published var subtitle = false
    @Published var landed = false
}

let hyprlandBlue = Theme.rgb(0x1FAFFF)
