import AppKit
import SwiftUI

struct ColorPopover: View {
    @ObservedObject var model: ConfigEditorModel

    var body: some View {
        VStack(spacing: 12) {
            ShadeSquare(color: Binding(get: { model.color }, set: { model.color = $0; model.hasColor = true; model.colorText = $0.hexRGB }))
                .frame(height: 140)
            GradientSlider(value: Binding(get: { model.color.h }, set: { update { $0.h = $1 }($0) }),
                           colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) },
                           knob: Color(hue: model.color.h, saturation: 1, brightness: 1))
            GradientSlider(value: Binding(get: { model.color.a }, set: { update { $0.a = $1 }($0) }),
                           colors: [model.color.color.opacity(0), Color(hue: model.color.h, saturation: model.color.s, brightness: model.color.b)],
                           knob: model.color.color, checker: true)
            HStack(spacing: 8) {
                OTextField(placeholder: "#RRGGBB, rgb() or hsl()", text: $model.colorText, mono: true, onSubmit: applyText)
                OButton("None", variant: .ghost, size: .sm) { model.set(color: nil); model.colorText = "" }.tooltip("No background color")
            }
        }
        .padding(14).frame(width: 260)
    }

    private func update(_ change: @escaping (inout HSBA, Double) -> Void) -> (Double) -> Void {
        { v in
            var c = model.color
            change(&c, v)
            model.color = c
            model.hasColor = true
            model.colorText = c.hexRGB
        }
    }

    private func applyText() {
        guard let c = HSBA(text: model.colorText) else { NSSound.beep(); return }
        model.set(color: c)
    }
}
