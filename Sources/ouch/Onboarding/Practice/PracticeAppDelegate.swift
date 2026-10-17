import AppKit
import SwiftUI

final class PracticeAppDelegate: NSObject, NSApplicationDelegate {
    private let parent: pid_t
    private let desk: [DemoApp], other: [DemoApp]
    private var parentWatch: DispatchSourceProcess?
    private var windows: [NSWindow] = []

    init(parent: pid_t, apps: [DemoApp]) {
        self.parent = parent
        desk = Array(apps.prefix(PracticeDesk.deskCount))
        other = Array(apps.dropFirst(PracticeDesk.deskCount))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        if parent <= 1 || kill(parent, 0) != 0 { exit(0) }
        let watch = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
        watch.setEventHandler { exit(0) }
        watch.resume()
        parentWatch = watch

        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Practice Desk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "Practice Desk", action: nil, keyEquivalent: "").submenu = appMenu
        NSApp.mainMenu = menu

        other.forEach { open($0, key: false) }
        for (i, app) in desk.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.12) { [weak self] in
                self?.open(app, key: i == 0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(desk.count) * 0.12 + 0.2) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.windows.first { $0.title == self?.desk.first?.title }?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func open(_ app: DemoApp, key: Bool) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = app.title
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: app.dark ? .darkAqua : .aqua)
        w.backgroundColor = NSColor(srgbRed: app.r, green: app.g, blue: app.b, alpha: 1)
        let host = NSHostingView(rootView: PracticeWindowView(app: app))
        host.sizingOptions = []
        w.contentView = host
        w.contentMinSize = NSSize(width: 160, height: 100)
        if let screen = NSScreen.main?.visibleFrame {
            let i = CGFloat(windows.count)
            w.setFrameOrigin(NSPoint(x: screen.midX - 320 + i * 28, y: screen.midY - 220 - i * 28))
        }
        if key { w.makeKeyAndOrderFront(nil) } else { w.orderFront(nil) }
        windows.append(w)
    }
}
