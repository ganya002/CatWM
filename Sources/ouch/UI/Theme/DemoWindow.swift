import AppKit
import CoreText
import SwiftUI

struct DemoWindow: View {
    let app: DemoApp
    var main = false
    var corner: CGFloat = 4

    private static let lights = [Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                                 Color(red: 0.16, green: 0.79, blue: 0.25)]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        GeometryReader { g in
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Self.lights[i].opacity(app.dark ? 0.85 : 1)).frame(width: 4, height: 4)
                }
                if g.size.width > 56 {
                    Text(app.title)
                        .font(Theme.body(6.5, .medium))
                        .foregroundStyle(app.dark ? Color.white.opacity(0.6) : Color.black.opacity(0.55))
                        .lineLimit(1)
                        .padding(.leading, 3)
                }
            }
            .padding(.horizontal, 5).padding(.top, 5)
            .opacity(g.size.width > 26 && g.size.height > 14 ? 1 : 0)
        }
        .background(app.color)
        .clipShape(shape)
        .overlay(shape.strokeBorder(main ? Theme.accent : (app.dark ? Color.white : Color.black).opacity(0.1),
                                    lineWidth: main ? 1.25 : 0.5))
    }
}
