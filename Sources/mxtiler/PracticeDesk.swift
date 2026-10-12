import AppKit
import SwiftUI

/// The onboarding tour's practice windows, run as `mxtiler practice <parent pid>`. They live in a
/// separate process because the window manager never tiles its own windows; this way the real
/// window manager tiles, focuses and parks them like any other app's, and the user's apps stay put.
enum PracticeDesk {
    enum Kind: CaseIterable { case terminal, notes, docs, inbox }

    static func title(_ k: Kind) -> String {
        switch k {
        case .terminal: "Terminal — zsh"
        case .notes: "Notes"
        case .docs: "Docs"
        case .inbox: "Inbox"
        }
    }

    /// The main app posts the indices of finished checklist items ("0,2") so the Notes window can tick them.
    static let progressNotification = Notification.Name("local.mxtiler.practice.progress")

    static func postProgress(_ done: Set<Int>) {
        DistributedNotificationCenter.default().postNotificationName(
            progressNotification, object: done.sorted().map(String.init).joined(separator: ","),
            userInfo: nil, deliverImmediately: true)
    }

    static func run(parent: pid_t) -> Never {
        let app = NSApplication.shared
        let delegate = PracticeAppDelegate(parent: parent)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        exit(0)
    }
}

private final class PracticeAppDelegate: NSObject, NSApplicationDelegate {
    private let parent: pid_t
    private var parentWatch: DispatchSourceProcess?
    private var windows: [NSWindow] = []
    private let checklist = Checklist()

    init(parent: pid_t) { self.parent = parent }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        // Never outlive the tour, even if mxtiler crashes or is killed.
        if parent <= 1 || kill(parent, 0) != 0 { exit(0) }
        let watch = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
        watch.setEventHandler { exit(0) }
        watch.resume()
        parentWatch = watch

        DistributedNotificationCenter.default().addObserver(forName: PracticeDesk.progressNotification, object: nil,
                                                            queue: .main) { [weak self] n in
            let items = (n.object as? String ?? "").split(separator: ",").compactMap { Int($0) }
            withAnimation(.easeOut(duration: 0.25)) { self?.checklist.done = Set(items) }
        }

        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Practice Desk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "Practice Desk", action: nil, keyEquivalent: "").submenu = appMenu
        NSApp.mainMenu = menu

        // The inbox opens first and without focus: it belongs on another workspace and gets parked
        // right away, and macOS must not hand it focus later (that would switch to its workspace).
        open(.inbox, key: false)
        for (i, kind) in [PracticeDesk.Kind.terminal, .notes, .docs].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.14) { [weak self] in
                self?.open(kind, key: kind == .terminal)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.windows.first { $0.title == PracticeDesk.title(.terminal) }?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func open(_ kind: PracticeDesk.Kind, key: Bool) {
        let dark = kind == .terminal
        // At least 500 wide, so "float small windows" never applies to them.
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = PracticeDesk.title(kind)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.backgroundColor = dark ? NSColor(white: 0.118, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        w.contentView = NSHostingView(rootView: PracticeWindowView(kind: kind, checklist: checklist))
        if let screen = NSScreen.main?.visibleFrame {
            let i = CGFloat(windows.count)
            w.setFrameOrigin(NSPoint(x: screen.midX - 320 + i * 28, y: screen.midY - 220 - i * 28))
        }
        if key { w.makeKeyAndOrderFront(nil) } else { w.orderFront(nil) }
        windows.append(w)
    }
}

private final class Checklist: ObservableObject {
    @Published var done: Set<Int> = []
}

private struct PracticeWindowView: View {
    let kind: PracticeDesk.Kind
    @ObservedObject var checklist: Checklist
    @Environment(\.controlActiveState) private var active

    private var dark: Bool { kind == .terminal }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar drawn here so it matches the content; the traffic lights are the real ones.
            ZStack {
                (dark ? Color(white: 0.17) : Color(white: 0.953))
                Text(PracticeDesk.title(kind)).font(Theme.body(12, .medium))
                    .foregroundStyle(dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }
            .frame(height: 30)
            .overlay(alignment: .bottom) { Rectangle().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)).frame(height: 0.5) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
        // The focused window wears a blue ring, so it's obvious where focus went.
        .overlay {
            if active == .key {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(red: 0, green: 122 / 255, blue: 1), lineWidth: 2.5)
                    .padding(2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .terminal: terminal
        case .notes: notes
        case .docs: docs
        case .inbox: inbox
        }
    }

    private var terminal: some View {
        let green = Color(red: 138 / 255, green: 226 / 255, blue: 138 / 255)
        func prompt(_ cmd: String) -> Text { Text("~").foregroundColor(green) + Text(" % " + cmd) }
        return VStack(alignment: .leading, spacing: 3) {
            prompt("mxtiler dispatch movefocus l")
            prompt("cat ~/.config/mxtiler/mxtiler.conf")
            Text("# keybinds: bind = MODS, key, dispatcher, args").foregroundColor(Color(white: 0.54))
            Text("bind = $mod, 1..0, workspace, 1..10")
            Text("bind = SUPER, capslock, submap, window")
            HStack(spacing: 0) {
                prompt("")
                Rectangle().fill(Color(white: 0.83)).frame(width: 7, height: 14)
            }
        }
        .font(Theme.mono(12, .regular))
        .foregroundStyle(Color(white: 0.83))
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var notes: some View {
        let items = ["Move focus between windows", "Swap two windows", "Visit another workspace"]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Practice desk").font(Theme.display(24))
            Text("These windows are pretend. Push them around as much as you like — your real apps stay exactly where they are.")
                .font(Theme.body(13)).foregroundStyle(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    let done = checklist.done.contains(i)
                    HStack(spacing: 7) {
                        Image(systemName: done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(done ? Color.green : Color.secondary)
                        Text(items[i]).strikethrough(done, color: .secondary)
                    }
                }
            }
            .font(Theme.body(13)).foregroundStyle(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255))
            .padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .foregroundStyle(Color(white: 0.11))
    }

    private var docs: some View {
        VStack(spacing: 0) {
            Text("mxtiler.app/docs/workspaces").font(Theme.body(11)).foregroundStyle(Color(white: 0.43))
                .frame(maxWidth: 340, minHeight: 20).padding(.horizontal, 12)
                .background(Capsule().fill(Color.black.opacity(0.06)))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color(white: 0.965))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5) }
            VStack(alignment: .leading, spacing: 6) {
                Text("DOCS").font(Theme.body(11, .semibold)).tracking(0.5).foregroundStyle(Color(white: 0.43))
                Text("Workspaces").font(Theme.display(26)).foregroundStyle(Color(white: 0.11))
                Text("Each display shows one workspace. A workspace remembers its layout and its last focused window, so switching is instant.")
                    .font(Theme.body(13)).foregroundStyle(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.vertical, 18)
        }
    }

    private var inbox: some View {
        let mail = [("Ada", "Layout ideas for the new monitor"), ("Release bot", "mxtiler 1.4 is out"), ("Sam", "Lunch on Thursday?")]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(mail.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(mail[i].0).font(Theme.body(13, .semibold)).foregroundStyle(Color(white: 0.11))
                    Text(mail[i].1).font(Theme.body(12)).foregroundStyle(Color(white: 0.43))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.5) }
            }
        }
    }
}
