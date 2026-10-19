import AppKit
import SwiftUI

enum PracticeDesk {
    static let deskCount = 5
    static let otherCount = 2

    static func pickApps() -> [DemoApp] {
        var dark = DemoApp.all.filter(\.dark).shuffled(), light = DemoApp.all.filter { !$0.dark }.shuffled()
        if Bool.random() { swap(&dark, &light) }
        return (0..<(deskCount + otherCount)).map { i in
            i.isMultiple(of: 2) ? dark.removeFirst() : light.removeFirst()
        }
    }

    static func run(parent: pid_t, titles: [String]) -> Never {
        let named = titles.compactMap { title in DemoApp.all.first { $0.title == title } }
        let apps = named.count == deskCount + otherCount ? named : pickApps()
        let app = NSApplication.shared
        let delegate = PracticeAppDelegate(parent: parent, apps: apps)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        exit(0)
    }
}
