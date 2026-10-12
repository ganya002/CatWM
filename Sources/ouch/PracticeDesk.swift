import AppKit
import SwiftUI

/// The onboarding tour's practice windows, run as `ouch practice <parent pid> [desk] [other]`. They live
/// in a separate process because the window manager never tiles its own windows; this way the real
/// window manager tiles, focuses and parks them like any other app's, and the user's apps stay put.
enum PracticeDesk {
    enum Kind: CaseIterable { case terminal, notes, docs, music, calendar, inbox, chat }

    /// Five windows on the desk, so there's plenty to move around, and two on a second workspace.
    static let deskKinds: [Kind] = [.terminal, .notes, .docs, .music, .calendar]
    static let otherKinds: [Kind] = [.inbox, .chat]

    static func title(_ k: Kind) -> String {
        switch k {
        case .terminal: "Terminal — zsh"
        case .notes: "Notes"
        case .docs: "Docs"
        case .music: "Music"
        case .calendar: "Calendar"
        case .inbox: "Inbox"
        case .chat: "Chat"
        }
    }

    /// The main app posts the indices of finished checklist items ("0,2") so the Notes window can tick them.
    static let progressNotification = Notification.Name("local.ouch.practice.progress")

    static func postProgress(_ done: Set<Int>) {
        DistributedNotificationCenter.default().postNotificationName(
            progressNotification, object: done.sorted().map(String.init).joined(separator: ","),
            userInfo: nil, deliverImmediately: true)
    }

    static func run(parent: pid_t, desk: String?, other: String?) -> Never {
        let app = NSApplication.shared
        let delegate = PracticeAppDelegate(parent: parent, desk: desk, other: other)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        exit(0)
    }
}

/// Each practice window looks like a different app, so it's obvious which one moved where.
private struct PracticeStyle {
    let dark: Bool
    let background: (CGFloat, CGFloat, CGFloat)
    let bar: (CGFloat, CGFloat, CGFloat)
    let accent: Color

    init(_ k: PracticeDesk.Kind) {
        switch k {
        case .terminal: (dark, background, bar, accent) = (true, (0.118, 0.118, 0.118), (0.17, 0.17, 0.17), Color(red: 0.54, green: 0.89, blue: 0.54))
        case .notes: (dark, background, bar, accent) = (false, (1, 0.98, 0.9), (0.99, 0.93, 0.7), Color(red: 0.86, green: 0.6, blue: 0))
        case .docs: (dark, background, bar, accent) = (false, (0.98, 0.98, 0.98), (0.953, 0.953, 0.953), Color(red: 0, green: 0.48, blue: 1))
        case .music: (dark, background, bar, accent) = (true, (0.13, 0.08, 0.22), (0.2, 0.12, 0.32), Color(red: 1, green: 0.36, blue: 0.56))
        case .calendar: (dark, background, bar, accent) = (false, (1, 1, 1), (0.98, 0.93, 0.93), Color(red: 0.92, green: 0.26, blue: 0.24))
        case .inbox: (dark, background, bar, accent) = (false, (0.95, 0.97, 1), (0.86, 0.91, 0.98), Color(red: 0.2, green: 0.45, blue: 0.85))
        case .chat: (dark, background, bar, accent) = (false, (0.93, 0.98, 0.95), (0.8, 0.93, 0.85), Color(red: 0.16, green: 0.66, blue: 0.4))
        }
    }

    var backgroundColor: Color { Color(red: background.0, green: background.1, blue: background.2) }
    var barColor: Color { Color(red: bar.0, green: bar.1, blue: bar.2) }
    var ink: Color { dark ? Color(white: 0.9) : Color(white: 0.11) }
    var secondary: Color { dark ? Color.white.opacity(0.55) : Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.8) }
}

private final class PracticeAppDelegate: NSObject, NSApplicationDelegate {
    private let parent: pid_t
    private let desk: String?, other: String?
    private var parentWatch: DispatchSourceProcess?
    private var windows: [NSWindow] = []
    private let checklist = Checklist()

    init(parent: pid_t, desk: String?, other: String?) {
        self.parent = parent
        self.desk = desk
        self.other = other
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        // Never outlive the tour, even if Ouch crashes or is killed.
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

        // The other workspace's windows open first and without focus: they get parked right away,
        // and macOS must not hand them focus later (that would switch to their workspace).
        PracticeDesk.otherKinds.forEach { open($0, key: false) }
        for (i, kind) in PracticeDesk.deskKinds.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.12) { [weak self] in
                self?.open(kind, key: kind == .terminal)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(PracticeDesk.deskKinds.count) * 0.12 + 0.2) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.windows.first { $0.title == PracticeDesk.title(.terminal) }?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func open(_ kind: PracticeDesk.Kind, key: Bool) {
        let style = PracticeStyle(kind)
        // At least 500 wide, so "float small windows" never applies to them.
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = PracticeDesk.title(kind)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: style.dark ? .darkAqua : .aqua)
        w.backgroundColor = NSColor(srgbRed: style.background.0, green: style.background.1, blue: style.background.2, alpha: 1)
        // The window manager decides the size. By default the hosting view derives a minimum size from
        // the SwiftUI content, and wrapping text measured at a narrow width made windows demand more
        // height than their tile had, so they refused their slots and the stack overlapped.
        let ws = PracticeDesk.otherKinds.contains(kind) ? other.map { ($0, false) } : desk.map { ($0, true) }
        let host = NSHostingView(rootView: PracticeWindowView(kind: kind, style: style, workspace: ws, checklist: checklist))
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

private final class Checklist: ObservableObject {
    @Published var done: Set<Int> = []
}

private struct PracticeWindowView: View {
    let kind: PracticeDesk.Kind
    let style: PracticeStyle
    /// The workspace this window opens on, and whether it's the practice desk (else the one to visit).
    let workspace: (name: String, desk: Bool)?
    @ObservedObject var checklist: Checklist
    @Environment(\.controlActiveState) private var active

    var body: some View {
        VStack(spacing: 0) {
            // Title bar drawn here so it matches the content; the traffic lights are the real ones.
            ZStack {
                style.barColor
                HStack(spacing: 6) {
                    Circle().fill(style.accent).frame(width: 7, height: 7)
                    Text(PracticeDesk.title(kind)).font(Theme.body(12, .semibold))
                        .foregroundStyle(style.dark ? Color.white.opacity(0.7) : Color.black.opacity(0.62))
                }
                if let workspace { badge(workspace).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10) }
            }
            .frame(height: 30)
            .overlay(alignment: .bottom) { Rectangle().fill(style.dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)).frame(height: 0.5) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(style.backgroundColor)
        .ignoresSafeArea()
        .clipped() // tiles can be smaller than the content
        // The focused window wears a ring, so it's obvious where focus went.
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

    /// "Workspace 4", blue on the practice desk and orange on the other one.
    private func badge(_ ws: (name: String, desk: Bool)) -> some View {
        let color = ws.desk ? Color(red: 0, green: 0.48, blue: 1) : Color(red: 0.96, green: 0.5, blue: 0)
        return HStack(spacing: 4) {
            Image(systemName: "square.grid.2x2.fill").font(.system(size: 8, weight: .bold))
            Text("Workspace \(ws.name)").font(Theme.body(10.5, .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .background(Capsule().fill(color))
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .terminal: terminal
        case .notes: notes
        case .docs: docs
        case .music: music
        case .calendar: calendar
        case .inbox: inbox
        case .chat: chat
        }
    }

    private var terminal: some View {
        let green = style.accent
        func prompt(_ cmd: String) -> Text { Text("~").foregroundColor(green) + Text(" % " + cmd) }
        return VStack(alignment: .leading, spacing: 3) {
            prompt("ouch dispatch movefocus l")
            prompt("cat ~/.config/ouch/ouch.conf")
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
        let items = ["Move focus between windows", "Swap two windows", "Grow and shrink the main pane",
                     "Zoom in on one window", "Visit another workspace"]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Practice checklist").font(Theme.heading(20)).foregroundStyle(style.ink)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items.indices, id: \.self) { i in
                    let done = checklist.done.contains(i)
                    HStack(spacing: 7) {
                        Image(systemName: done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(done ? Color.green : style.accent)
                            .contentTransition(.symbolEffect(.replace))
                            .animation(.default, value: done)
                        Text(items[i]).strikethrough(done, color: .secondary)
                    }
                }
            }
            .font(Theme.body(13)).foregroundStyle(style.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var docs: some View {
        VStack(spacing: 0) {
            Text("ouch.app/docs/workspaces").font(Theme.body(11)).foregroundStyle(Color(white: 0.43))
                .frame(maxWidth: 340, minHeight: 20).padding(.horizontal, 12)
                .background(Capsule().fill(Color.black.opacity(0.06)))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Color(white: 0.965))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5) }
            VStack(alignment: .leading, spacing: 6) {
                Text("DOCS").font(Theme.body(11, .semibold)).tracking(0.5).foregroundStyle(style.accent)
                Text("Workspaces").font(Theme.heading(24)).foregroundStyle(style.ink)
                Text("Each display shows one workspace. A workspace remembers its layout and last focused window.")
                    .font(Theme.body(13)).foregroundStyle(style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    private var music: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [style.accent, Color(red: 1, green: 0.62, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "music.note").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Tiled Hearts").font(Theme.body(15, .semibold)).foregroundStyle(style.ink)
                Text("The Gaps · Even Split").font(Theme.body(12)).foregroundStyle(style.secondary)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(style.accent).frame(width: g.size.width * 0.38)
                    }
                }
                .frame(maxWidth: 220, maxHeight: 4)
                .padding(.top, 6)
                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill").font(.system(size: 18))
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 13)).foregroundStyle(style.ink)
                .padding(.top, 6)
            }
        }
        .lineLimit(1)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [style.backgroundColor, Color(red: 0.06, green: 0.04, blue: 0.11)], startPoint: .top, endPoint: .bottom))
    }

    private var calendar: some View {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        let events: [[(String, Color)]] = [
            [("Standup", style.accent)], [("Design", .purple), ("Gym", .green)], [("1:1", .orange)],
            [("Standup", style.accent), ("Review", .blue)], [("Demo", .pink)],
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("October").font(Theme.heading(20)).foregroundStyle(style.ink)
                Text("Week 42").font(Theme.body(12)).foregroundStyle(style.accent)
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(days.indices, id: \.self) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(days[d]).font(Theme.body(10.5, .semibold)).foregroundStyle(style.secondary)
                        ForEach(events[d].indices, id: \.self) { e in
                            Text(events[d][e].0).font(Theme.body(10.5, .medium)).foregroundStyle(events[d][e].1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 5).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(events[d][e].1.opacity(0.14)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var inbox: some View {
        let mail = [("Ada", "Layout ideas for the new monitor"), ("Release bot", "Ouch 1.4 is out"), ("Sam", "Lunch on Thursday?")]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(mail.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle().fill(i == 0 ? style.accent : Color.clear).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mail[i].0).font(Theme.body(13, .semibold)).foregroundStyle(style.ink)
                        Text(mail[i].1).font(Theme.body(12)).foregroundStyle(style.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.5) }
            }
        }
        .lineLimit(1)
    }

    private var chat: some View {
        let lines: [(String, Bool)] = [("Is the new tiler any good?", false), ("Tiling everything now", true), ("Even the music player?", false)]
        return VStack(spacing: 8) {
            ForEach(lines.indices, id: \.self) { i in
                let mine = lines[i].1
                Text(lines[i].0).font(Theme.body(13))
                    .foregroundStyle(mine ? Color.white : style.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(mine ? style.accent : Color.white))
                    .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            }
        }
        .lineLimit(1)
        .padding(14)
    }
}
