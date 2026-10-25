import AppKit
import SwiftUI

struct ColorPopover: View {
    @ObservedObject var model: ConfigEditorModel

    var body: some View {
        VStack(spacing: 12) {
            ShadeSquare(color: Binding(get: { model.color }, set: {
                model.color = $0; model.hasColor = true; model.colorText = $0.hexRGB
            }))
                .frame(height: 140)
            GradientSlider(value: Binding(get: { model.color.hue }, set: { update { $0.hue = $1 }($0) }),
                           colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
                               Color(hue: $0, saturation: 1, brightness: 1)
                           },
                           knob: Color(hue: model.color.hue, saturation: 1, brightness: 1), label: "Hue")
            GradientSlider(value: Binding(get: { model.color.alpha }, set: { update { $0.alpha = $1 }($0) }),
                           colors: [model.color.color.opacity(0),
                                    Color(hue: model.color.hue, saturation: model.color.saturation,
                                          brightness: model.color.brightness)],
                           knob: model.color.color, checker: true, label: "Opacity")
            HStack(spacing: 8) {
                OTextField(placeholder: "#RRGGBB, rgb() or hsl()", text: $model.colorText, mono: true,
                           onSubmit: applyText)
                OButton("None", variant: .ghost, size: .small) {
                    model.set(color: nil); model.colorText = ""
                }
            }
        }
        .padding(14).frame(width: 260)
    }

    private func update(_ change: @escaping (inout HSBA, Double) -> Void) -> (Double) -> Void {
        { value in
            var color = model.color
            change(&color, value)
            model.color = color
            model.hasColor = true
            model.colorText = color.hexRGB
        }
    }

    private func applyText() {
        guard let color = HSBA(text: model.colorText) else { NSSound.beep(); return }
        let current = model.color
        model.set(color: color.hexRGB == current.hexRGB && model.hasColor ? current : color)
    }
}
