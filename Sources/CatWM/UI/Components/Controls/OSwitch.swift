import AppKit
import CatWMKit
import SwiftUI

struct OSwitch: View {
    @Binding var isOn: Bool
    let label: String
    @StateObject private var state = SwitchState()
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    final class SwitchState: ObservableObject {
        @Published var pressed = false
        @Published var drag: CGFloat?
    }

    var body: some View {
        let shownOn = state.drag.map { $0 > 7 } ?? isOn
        let width: CGFloat = state.pressed ? 18 : 14
        let x = state.drag.map { min($0, 14 - (width - 14)) } ?? (isOn ? 14 - (width - 14) : 0)
        ZStack(alignment: .leading) {
            Capsule().fill(shownOn ? Theme.accent : Theme.surfaceSunken)
            Capsule().strokeBorder(Theme.borderControl, lineWidth: 1).opacity(shownOn ? 0 : 1)
            Capsule().fill(shownOn ? Theme.onAccent : Theme.borderControl)
                .frame(width: width, height: 14)
                .offset(x: 3 + x)
        }
        .frame(width: 34, height: 20)
        .contentShape(Capsule())
        .animation(reduceMotion ? Motion.fade : Motion.spring, value: isOn)
        .animation(reduceMotion ? Motion.fade : Motion.spring, value: state.pressed)
        .animation(Motion.fade, value: shownOn)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !state.pressed { state.pressed = true }
                if abs(gesture.translation.width) > 3 || state.drag != nil {
                    state.drag = min(max((isOn ? 14 : 0) + gesture.translation.width, 0), 14)
                }
            }
            .onEnded { _ in
                if let drag = state.drag { isOn = drag > 7 } else { isOn.toggle() }
                state.drag = nil
                state.pressed = false
            })
        .focusable()
        .onKeyPress(keys: [.space, .return]) { _ in isOn.toggle(); return .handled }
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { isOn.toggle() }
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var switchExamples: some View {
        OSwitch(isOn: $model.isOn, label: "Tiling")
        OSwitch(isOn: $model.off, label: "Focus follows mouse")
        OSwitch(isOn: $model.isOn, label: "Disabled").disabled(true)
    }
}
#endif
