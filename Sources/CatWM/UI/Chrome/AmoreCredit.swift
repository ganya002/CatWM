import CatWMKit
import SwiftUI

struct AmoreCredit: View {
    @StateObject private var hover = Flag()
    @StateObject private var model = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    final class Model: ObservableObject { @Published var beats = 0 }

    var body: some View {
        let hovering = hover.isOn, reduce = reduceMotion, beats = model.beats
        return Button {
            openURL(URL(string: "https://amore.computer")!)
            model.beats += 1
        } label: {
            HStack(spacing: 4) {
                Text("shipped with")
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.danger)
                    .squish(on: beats, anchor: .center)
                Text("Amore").fontWeight(.medium)
                    .offset(y: hovering && !reduce ? -0.5 : 0)
                    .overlay(alignment: .bottom) {
                        Capsule().frame(height: 1)
                            .scaleEffect(x: hovering ? 1 : 0, anchor: .leading)
                            .opacity(hovering ? 1 : 0)
                            .offset(y: 2)
                    }
            }
            .font(Theme.body(11))
            .foregroundStyle(Theme.inkMuted.opacity(hovering ? 1 : 0.6))
            .animation(reduce ? Motion.fade : Motion.spring, value: hovering)
        }
        .buttonStyle(PressScale(scale: reduce ? 1 : 0.95))
        .onHover { hover.isOn = $0 }
    }
}
