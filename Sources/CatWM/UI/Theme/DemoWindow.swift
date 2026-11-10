import AppKit
import CatWMKit
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
        GeometryReader { geometry in
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Self.lights[i].opacity(app.dark ? 0.85 : 1)).frame(width: 4, height: 4)
                }
                if geometry.size.width > 56 {
                    Text(app.title)
                        .font(Theme.body(6.5, .medium))
                        .foregroundStyle(app.dark ? Color.white.opacity(0.6) : Color.black.opacity(0.55))
                        .lineLimit(1)
                        .padding(.leading, 3)
                }
            }
            .padding(.horizontal, 5).padding(.top, 5)
            .opacity(geometry.size.width > 26 && geometry.size.height > 14 ? 1 : 0)
        }
        .background(app.color)
        .clipShape(shape)
        .overlay(shape.strokeBorder(main ? Theme.accent : (app.dark ? Color.white : Color.black).opacity(0.1),
                                    lineWidth: main ? 1.25 : 0.5))
    }
}

struct DemoApp: Equatable {
    let title: String
    let dark: Bool
    let red: Double, green: Double, blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    static let all: [DemoApp] = [
        DemoApp(title: "Terminal", dark: true, red: 0.13, green: 0.13, blue: 0.15),
        DemoApp(title: "Notes", dark: false, red: 0.95, green: 0.95, blue: 0.96),
        DemoApp(title: "Music", dark: true, red: 0.2, green: 0.21, blue: 0.26),
        DemoApp(title: "Mail", dark: false, red: 0.88, green: 0.92, blue: 0.97),
        DemoApp(title: "Code", dark: true, red: 0.11, green: 0.15, blue: 0.21),
        DemoApp(title: "Messages", dark: false, red: 0.86, green: 0.94, blue: 0.9),
        DemoApp(title: "Photos", dark: true, red: 0.26, green: 0.19, blue: 0.26),
        DemoApp(title: "Calendar", dark: false, red: 0.98, green: 0.93, blue: 0.89),
        DemoApp(title: "Finder", dark: false, red: 0.92, green: 0.9, blue: 0.98),
        DemoApp(title: "Maps", dark: false, red: 0.89, green: 0.93, blue: 0.85),
        DemoApp(title: "Figma", dark: true, red: 0.16, green: 0.2, blue: 0.18),
        DemoApp(title: "Podcasts", dark: true, red: 0.24, green: 0.17, blue: 0.14)
    ]

    static func pick(avoiding taken: [DemoApp] = []) -> DemoApp {
        all.filter { !taken.contains($0) }.randomElement() ?? all.randomElement() ?? all[0]
    }
}
