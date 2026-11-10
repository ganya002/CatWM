import AppKit
import CatWMKit
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

    func applicationDidFinishLaunching(_: Notification) {
        Theme.registerFonts()
        if parent <= 1 || kill(parent, 0) != 0 { exit(0) }
        let watch = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
        watch.setEventHandler { exit(0) }
        watch.resume()
        parentWatch = watch

        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Practice Desk", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
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

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

    private func open(_ app: DemoApp, key: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = app.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: app.dark ? .darkAqua : .aqua)
        window.backgroundColor = NSColor(srgbRed: app.red, green: app.green, blue: app.blue, alpha: 1)
        let host = NSHostingView(rootView: PracticeWindowView(app: app))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 160, height: 100)
        if let screen = NSScreen.main?.visibleFrame {
            let offset = CGFloat(windows.count) * 28
            window.setFrameOrigin(NSPoint(x: screen.midX - 320 + offset, y: screen.midY - 220 - offset))
        }
        if key { window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }
        windows.append(window)
    }
}

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

struct PracticeWindowView: View {
    let app: DemoApp
    @Environment(\.controlActiveState) private var active

    var body: some View {
        Text(app.title)
            .font(Theme.body(13, .medium))
            .foregroundStyle(app.dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55))
            .lineLimit(1)
            .padding(.leading, 78)
            .frame(height: 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(app.color)
            .ignoresSafeArea()
            .overlay {
                if active == .key {
                    RoundedRectangle(cornerRadius: 11, style: .continuous) // style-ok: follows the macOS window corner
                        .strokeBorder(Theme.accent, lineWidth: 2.5)
                        .padding(2)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
    }
}
