import AppKit
import CoreText
import SwiftUI

struct DemoApp: Equatable {
    let title: String
    let dark: Bool
    let r: Double, g: Double, b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    static let all: [DemoApp] = [
        DemoApp(title: "Terminal", dark: true, r: 0.13, g: 0.13, b: 0.15),
        DemoApp(title: "Notes", dark: false, r: 0.95, g: 0.95, b: 0.96),
        DemoApp(title: "Music", dark: true, r: 0.2, g: 0.21, b: 0.26),
        DemoApp(title: "Mail", dark: false, r: 0.88, g: 0.92, b: 0.97),
        DemoApp(title: "Code", dark: true, r: 0.11, g: 0.15, b: 0.21),
        DemoApp(title: "Messages", dark: false, r: 0.86, g: 0.94, b: 0.9),
        DemoApp(title: "Photos", dark: true, r: 0.26, g: 0.19, b: 0.26),
        DemoApp(title: "Calendar", dark: false, r: 0.98, g: 0.93, b: 0.89),
        DemoApp(title: "Finder", dark: false, r: 0.92, g: 0.9, b: 0.98),
        DemoApp(title: "Maps", dark: false, r: 0.89, g: 0.93, b: 0.85),
        DemoApp(title: "Figma", dark: true, r: 0.16, g: 0.2, b: 0.18),
        DemoApp(title: "Podcasts", dark: true, r: 0.24, g: 0.17, b: 0.14),
    ]

    static func pick(avoiding taken: [DemoApp] = []) -> DemoApp {
        (all.filter { !taken.contains($0) }.randomElement() ?? all.randomElement())!
    }
}
