import AppKit
import SwiftUI

struct KeyHelpView: View {
    @ObservedObject var model: KeyHelpModel
    let margin: CGFloat

    var body: some View {
        keyboard
            .panelEntrance(model.shown, style: model.motion, radius: 20)
            .padding(margin)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Keyboard help")
    }

    private var keyboard: some View {
        let scale = model.keyboardWidth / KeyHintKeyboard.size(scale: 1).width
        return KeyHintKeyboard(binds: model.hints, pressed: model.pressed, hot: model.hot, scale: scale)
            .environment(\.keyTile, model.motion == .tile ? .tile(shown: model.shown) : .rise)
    }
}
