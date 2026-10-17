import AppKit
import SwiftUI

struct ShadeSquare: View {
    @Binding var color: HSBA

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.white, Color(hue: color.h, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                OKnob(color: Color(hue: color.h, saturation: color.s, brightness: color.b), size: 18)
                    .position(x: color.s * geo.size.width, y: (1 - color.b) * geo.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                var c = color
                c.s = min(max(v.location.x / geo.size.width, 0), 1)
                c.b = 1 - min(max(v.location.y / geo.size.height, 0), 1)
                color = c
            })
        }
        .accessibilityLabel("Color shade")
    }
}
