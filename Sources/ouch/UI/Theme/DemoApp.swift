import AppKit
import CoreText
import SwiftUI

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
