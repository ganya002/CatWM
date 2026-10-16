// Onboarding: the tour's practice windows, run as a separate process.
import AppKit
import SwiftUI

/// The onboarding tour's practice windows, run as `ouch practice <parent pid> <titles>`. They live
/// in a separate process because the window manager never tiles its own windows; this way the real
/// window manager tiles, focuses and parks them like any other app's, and the user's apps stay put.
enum PracticeDesk {
    /// Five windows on the desk, so there's plenty to move around, and two on a second workspace.
    static let deskCount = 5
    static let otherCount = 2

    /// A random cast of apps, desk first. Light and dark alternate so neighbours always stand apart.
    static func pickApps() -> [DemoApp] {
        var dark = DemoApp.all.filter(\.dark).shuffled(), light = DemoApp.all.filter { !$0.dark }.shuffled()
        if Bool.random() { swap(&dark, &light) }
        return (0..<(deskCount + otherCount)).map { i in i.isMultiple(of: 2) ? dark.removeFirst() : light.removeFirst() }
    }

    static func run(parent: pid_t, titles: [String]) -> Never {
        let named = titles.compactMap { t in DemoApp.all.first { $0.title == t } }
        let apps = named.count == deskCount + otherCount ? named : pickApps()
        let app = NSApplication.shared
        let delegate = PracticeAppDelegate(parent: parent, apps: apps)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        exit(0)
    }
}

private final class PracticeAppDelegate: NSObject, NSApplicationDelegate {
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
        // Never outlive the tour, even if Ouch crashes or is killed.
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

        // The other workspace's windows open first and without focus: they get parked right away,
        // and macOS must not hand them focus later (that would switch to their workspace).
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
        // At least 500 wide, so "float small windows" never applies to them.
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = app.title
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: app.dark ? .darkAqua : .aqua)
        w.backgroundColor = NSColor(srgbRed: app.r, green: app.g, blue: app.b, alpha: 1)
        // The window manager decides the size, so the hosting view mustn't impose one of its own.
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

/// A flat tone with the title beside the real traffic lights, so it's obvious which window moved where.
private struct PracticeWindowView: View {
    let app: DemoApp
    @Environment(\.controlActiveState) private var active

    var body: some View {
        Text(app.title)
            .font(Theme.body(13, .medium))
            .foregroundStyle(app.dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55))
            .lineLimit(1)
            .padding(.leading, 78) // clear of the traffic lights
            .frame(height: 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(app.color)
            .ignoresSafeArea()
            // The focused window wears a ring, so it's obvious where focus went.
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
