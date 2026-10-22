import AppKit
import SwiftUI

struct Wordmark: View {
    private final class Model: ObservableObject {
        @Published var hover = false
        @Published var bumps = 0
    }
    @StateObject private var model = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("CatWM").font(Theme.wordmark(26)).tracking(-0.5)
            .rotationEffect(.degrees(model.hover && !reduceMotion ? -6 : 0), anchor: .bottomLeading)
            .squish(on: model.bumps)
            .animation(Motion.snap, value: model.hover)
            .onHover { model.hover = $0 }
            .onTapGesture { model.bumps += 1 }
            .accessibilityAddTraits(.isHeader)
    }
}
