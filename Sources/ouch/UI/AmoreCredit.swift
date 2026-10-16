// UI: the small "shipped with Amore" credit.
import SwiftUI

/// Tiny "shipped with" credit. Hover brightens it, swells the heart and draws an underline under
/// "Amore"; a click dips the whole line and pops the heart.
struct AmoreCredit: View {
    @StateObject private var hover = Flag()
    @StateObject private var model = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    final class Model: ObservableObject { @Published var beats = 0 }

    var body: some View {
        let hovering = hover.on, reduce = reduceMotion, beats = model.beats
        return Button {
            openURL(URL(string: "https://amore.computer")!)
            model.beats += 1
        } label: {
            HStack(spacing: 4) {
                Text("shipped with")
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.danger)
                    .scaleEffect(hovering && !reduce ? 1.25 : 1)
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
        .onHover { hover.on = $0 }
        .tooltip("Updates delivered by Amore")
    }
}
