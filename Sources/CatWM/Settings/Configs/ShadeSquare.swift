import AppKit
import SwiftUI

struct ShadeSquare: View {
    @Binding var color: HSBA

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.white, Color(hue: color.hue, saturation: 1, brightness: 1)],
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                OKnob(color: Color(hue: color.hue, saturation: color.saturation, brightness: color.brightness),
                      size: 18)
                    .position(x: color.saturation * geo.size.width, y: (1 - color.brightness) * geo.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                var shade = color
                shade.saturation = min(max(drag.location.x / geo.size.width, 0), 1)
                shade.brightness = 1 - min(max(drag.location.y / geo.size.height, 0), 1)
                color = shade
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Color shade")
        .accessibilityValue("Saturation \(Int((color.saturation * 100).rounded())) percent, "
            + "brightness \(Int((color.brightness * 100).rounded())) percent")
    }
}
