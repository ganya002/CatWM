// MenuBar: the menu under the menu bar item (items, search, Layout submenu).
import AppKit
import SwiftUI

// The menu under the menu bar item: a Surface `md` on glass with a search field, the essentials, where
// you are, then the Layout submenu. The search reads the same items, so the two never
// disagree. Rows show window-mode keys; the label row states the chord that enters the mode once.

// MARK: - Items

struct MenuItem: Identifiable {
    enum Kind { case action, check, radio, sub, label, separator, essentials, workspaces, layoutPicker, attention, footer }

    var id: String
    var kind: Kind = .action
    var label = ""
    var symbol: String? = nil
    /// An app icon in place of a symbol.
    var image: NSImage? = nil
    var shortcut: [String] = []
    /// The current choice, shown muted after a submenu's label.
    var value: String? = nil
    var checked = false
    var danger = false
    var enabled = true
    /// Only reachable through search (aliases for things inside a custom control).
    var hidden = false
    var keywords = ""
    var width: CGFloat = Theme.submenuWidth
    var children: [MenuItem] = []
    /// Leaves the menu open after running (toggles you want to see flip).
    var keepOpen = false
    /// Turns its symbol on use: Retile, Reload, Settings.
    var rotates = false
    /// A count shown in a pill before the shortcut.
    var badge: Int? = nil
    /// A notification dot on the symbol: something here is waiting (a crash report).
    var dot = false
    var action: (() -> Void)? = nil

    var selectable: Bool {
        guard enabled, !hidden else { return false }
        return [.action, .check, .radio, .sub, .footer].contains(kind)
    }

    static func sep(_ id: String) -> MenuItem { MenuItem(id: id, kind: .separator) }
    static func label(_ id: String, _ text: String, shortcut: [String] = []) -> MenuItem {
        MenuItem(id: id, kind: .label, label: text, shortcut: shortcut)
    }
}

/// Keys for actions as the config binds them: window-mode keys first, then global ones.
struct ShortcutIndex {
    private var mode: [String: [String]] = [:]
    private var global: [String: [String]] = [:]
    /// The configured window mode name, if there is one.
    var modeName: String? = nil
    /// The chord that enters window mode, e.g. ⌘⇪.
    var modeChord: [String] = []

    init() {
        let text = (try? String(contentsOf: Config.url, encoding: .utf8)) ?? defaultText
        let doc = ConfigDocument(text: text)
        let modeBind = doc.binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && $0.args.lowercased() != "reset" }
        if let modeBind {
            modeName = modeBind.args
            modeChord = doc.prettyShortcut(modeBind)
        }
        func table(_ submap: String) -> [String: [String]] {
            var out: [String: [String]] = [:]
            for a in doc.keyActions(in: submap) where out[a.title] == nil {
                out[a.title] = ConfigDocument.modifierCaps(a.flags) + [ConfigDocument.capLabel(a.key)]
            }
            return out
        }
        if let m = modeName { mode = table(m) }
        global = table("")
    }

    /// The keys for a catalog action, without the mode chord.
    func keys(_ dispatcher: String, _ args: String = "") -> [String] {
        guard let title = Actions.all.first(where: { $0.dispatcher == dispatcher && $0.args == args })?.title else { return [] }
        return mode[title] ?? global[title] ?? []
    }
}

// MARK: - Model

final class MenuModel: ObservableObject {
    @Published var items: [MenuItem] = []
    @Published var query = "" {
        // Leading spaces are dropped, so a query of only spaces is no query rather than one matching nothing.
        didSet { if query.first?.isWhitespace == true { query = String(query.drop { $0.isWhitespace }) } }
    }
    /// Ids of the open submenus, one per level below the root.
    @Published var path: [String] = []
    /// Highlighted item per level (0 is the root or the search results).
    @Published var highlight: [Int: String] = [:]
    @Published var appeared = false
    /// Row frames in the menu's coordinate space, for placing submenus beside their row.
    @Published var rowFrames: [String: CGRect] = [:]
    @Published var columnHeights: [Int: CGFloat] = [:]
    /// Submenus open to the left when the item sits near the right edge of the screen.
    var opensLeft = true
    var close: () -> Void = {}
    /// The status menu has a search field; pop-up menus elsewhere don't.
    var searchable = true
    /// Where the items come from: live state for the status menu, a fixed list for a pop-up.
    var source: () -> [MenuItem] = MenuModel.build

    private var openWork: DispatchWorkItem?
    /// The submenu row `openWork` opens.
    private var opening: String?
    private var trimWork: DispatchWorkItem?
    /// The level `trimWork` trims to.
    private var trimLevel = 0

    // MARK: Building

    func rebuild() {
        items = source()
    }

    func reset() {
        query = ""
        path = []
        highlight = [:]
        appeared = false
        openWork?.cancel()
        trimWork?.cancel()
    }

    /// The real menu, from live state.
    static func build() -> [MenuItem] {
        let wm = WindowManager.shared
        let keys = ShortcutIndex()
        let axGranted = Permission.accessibility.isGranted
        let trusted = axGranted && wm.isStarted
        let state = wm.menuBarState()
        let layout = state?.layout
        var out: [MenuItem] = []

        if !axGranted {
            out.append(MenuItem(id: "attention", kind: .attention, label: "Ouch needs Accessibility", keywords: "permission grant",
                                action: { Permission.accessibility.request() }))
        }

        // Hidden alias so search finds it.
        out.append(MenuItem(id: "tiling", kind: .check, label: "Tiling", symbol: "rectangle.split.3x1", shortcut: keys.keys("toggletiling"),
                            checked: wm.tilingEnabled, enabled: trusted, hidden: true, keywords: "enable disable pause toggle",
                            keepOpen: true, action: { wm.toggleTiling() }))

        // Where you are.
        let wsName = state?.workspace.map { "Workspace \($0)" } ?? "Desktop"
        out.append(.label("where", layout.map { "\(wsName) · \($0.title)" } ?? wsName))
        let summary = wm.workspaceSummary()
        if wm.config.virtualWorkspaces && trusted {
            out.append(MenuItem(id: "workspaces", kind: .workspaces))
            let highest = summary.all.compactMap { Int($0.name) }.max() ?? 0
            for n in 1...max(9, min(highest, 10)) {
                out.append(MenuItem(id: "ws-\(n)", label: "Go to Workspace \(n)", shortcut: keys.keys("workspace", "\(n)"),
                                    hidden: true, keywords: "switch space desktop", action: { wm.showWorkspace("\(n)") }))
            }
        }
        out.append(.sep("s1"))

        // Layout.
        var layoutItems: [MenuItem] = [
            MenuItem(id: "picker", kind: .layoutPicker),
            MenuItem(id: "next-layout", label: "Next Layout", symbol: "chevron.right", shortcut: keys.keys("cyclelayout", "next"),
                     enabled: trusted, hidden: true, keepOpen: true, action: { wm.dispatch("cyclelayout", "next") }),
            MenuItem(id: "prev-layout", label: "Previous Layout", symbol: "chevron.left", shortcut: keys.keys("cyclelayout", "prev"),
                     enabled: trusted, hidden: true, keepOpen: true, action: { wm.dispatch("cyclelayout", "prev") }),
        ]
        layoutItems += Layout.allCases.map { l in
            MenuItem(id: "layout-\(l.rawValue)", kind: .radio, label: l.title, shortcut: keys.keys("layout", l.rawValue), checked: l == layout,
                     enabled: trusted, hidden: true, keywords: "layout \(l.blurb)", action: { wm.dispatch("layout", l.rawValue) })
        }
        out.append(MenuItem(id: "layout", kind: .sub, label: "Layout", symbol: "square.grid.2x2", value: layout?.title,
                            enabled: trusted, width: 276, children: layoutItems))

        if wm.config.virtualWorkspaces && trusted {
            let incoming = wm.windowsOnOtherDesktops().map { w in
                let app = NSRunningApplication(processIdentifier: w.pid)
                let title = w.element.string(kAXTitleAttribute) ?? "Untitled"
                return MenuItem(id: "bring-\(w.id)", label: title.isEmpty ? "Untitled" : title, image: app?.icon,
                                value: app?.localizedName, keywords: "bring import window desktop space",
                                action: { wm.bringWindowHere(w) })
            }
            if !incoming.isEmpty {
                out.append(MenuItem(id: "bring-window", kind: .sub, label: "Bring Window Here", symbol: "rectangle.badge.arrow.down",
                                    keywords: "import other desktops spaces", width: 340, children: incoming))
            }
        }

        out.append(.sep("s2"))

        out.append(MenuItem(id: "settings", label: "Settings…", symbol: "gearshape", shortcut: ["⌘", ","], keywords: "preferences options",
                            rotates: true, action: { SettingsWindow.shared.show(pane: nil) }))
        let paused = TutorialLesson.paused
        out.append(MenuItem(id: "tutorial", label: paused == nil ? "Keyboard Tutorial…" : "Resume Tutorial…", symbol: "graduationcap",
                            value: paused?.name, enabled: trusted, keywords: "learn practice drill keys lessons onboarding help",
                            action: { Onboarding.shared.startTutorial() }))
        out.append(MenuItem(id: "help", kind: .sub, label: "Help", symbol: "questionmark.circle", children: [
            MenuItem(id: "map", label: "Shortcut Map", symbol: "keyboard", shortcut: ["⌘", "/"], keywords: "keys overview cheat sheet",
                     action: { SettingsWindow.shared.show(pane: .shortcuts, map: true) }),
            MenuItem(id: "keyhelp", label: "Keyboard Help", symbol: "keyboard.badge.ellipsis", shortcut: keys.modeChord,
                     enabled: trusted, hidden: true, keywords: "keys overlay cheat sheet window mode", action: { KeyHelp.shared.showFromMenu(preferredMode: keys.modeName) }),
            MenuItem(id: "tour", label: "Quick Tour", symbol: "play.circle", enabled: trusted,
                     keywords: "learn tutorial onboarding keyboard tour", action: { Onboarding.shared.startTour() }),
            MenuItem(id: "tutorial-restart", label: "Restart Tutorial", symbol: "arrow.counterclockwise", enabled: trusted,
                     hidden: true, keywords: "learn tutorial start over", action: { Onboarding.shared.startTutorial(fromStart: true) }),
            MenuItem(id: "tips", kind: .check, label: "Show Tips", checked: Tips.shared.enabled, hidden: true, keywords: "hints help tooltips",
                     keepOpen: true, action: { Tips.shared.enabled.toggle() }),
            MenuItem(id: "reload", label: "Reload Config", symbol: "arrow.triangle.2.circlepath", shortcut: keys.keys("reload"),
                     hidden: true, keywords: "refresh file", keepOpen: true, rotates: true, action: { wm.reload() }),
            MenuItem(id: "updates", label: "Check for Updates…", symbol: "arrow.down.circle", keywords: "version upgrade",
                     action: { AppDelegate.checkForUpdates() }),
        ]))
        out.append(.sep("s3"))
        out.append(MenuItem(id: "quit", kind: .footer, label: "Quit Ouch", shortcut: ["⌘", "Q"], keywords: "exit",
                            action: { NSApp.terminate(nil) }))
        return out
    }

    // MARK: Lookup

    func item(_ id: String, in list: [MenuItem]? = nil) -> MenuItem? {
        for i in list ?? items {
            if i.id == id { return i }
            if let found = item(id, in: i.children) { return found }
        }
        return nil
    }

    /// Items of a level: the root, or the open submenu above it.
    func column(_ level: Int) -> [MenuItem] {
        if !query.isEmpty { return level == 0 ? results.map(\.item) : [] }
        guard level > 0 else { return items }
        guard level <= path.count, let parent = item(path[level - 1]) else { return [] }
        return parent.children
    }

    /// Every leaf the search can run, with where it lives.
    var results: [(item: MenuItem, crumb: String)] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var out: [(MenuItem, String)] = []
        func walk(_ list: [MenuItem], _ crumb: [String]) {
            for var i in list {
                switch i.kind {
                case .sub: walk(i.children, crumb + [i.label])
                case .action, .check, .radio, .footer, .attention:
                    let text = "\(i.label) \(i.keywords) \(crumb.joined(separator: " "))".lowercased()
                    guard i.enabled, words.allSatisfy({ text.contains($0) }) else { continue }
                    i.hidden = false
                    if i.kind == .footer || i.kind == .attention { i.kind = .action }
                    out.append((i, crumb.joined(separator: " › ")))
                default: break
                }
            }
        }
        walk(items, [])
        return out
    }

    // MARK: Pointer

    func hover(_ item: MenuItem, level: Int) {
        guard item.selectable else { return }
        highlight[level] = item.id
        trimWork?.cancel()
        openWork?.cancel()
        let open = path.count > level ? path[level] : nil
        if item.kind == .sub {
            guard open != item.id else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                withAnimation(Motion.easeOut) { self.path = Array(self.path.prefix(level)) + [item.id] }
            }
            openWork = work
            opening = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        } else if open != nil {
            // A grace period, so a diagonal move toward the open submenu doesn't close it.
            let work = DispatchWorkItem { [weak self] in self?.trim(to: level) }
            trimWork = work
            trimLevel = level
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    /// The pointer left a row: it goes dark, unless its submenu is open, and its submenu no longer opens.
    func unhover(_ item: MenuItem, level: Int) {
        if opening == item.id { openWork?.cancel(); opening = nil }
        let open = path.count > level ? path[level] : nil
        if highlight[level] == item.id, open != item.id { highlight[level] = nil }
    }

    /// The pointer reached a submenu: keep it, and its parent row lit. Coming back into the column
    /// that asked for the trim doesn't stop it.
    func enterColumn(_ level: Int) {
        if level > trimLevel { trimWork?.cancel() }
        if level > 0, level <= path.count { highlight[level - 1] = path[level - 1] }
    }

    func trim(to level: Int) {
        guard path.count > level else { return }
        withAnimation(Motion.easeOut) { path = Array(path.prefix(level)) }
        for l in highlight.keys where l > level { highlight[l] = nil }
    }

    // MARK: Keyboard

    var keyLevel: Int { query.isEmpty ? min(path.count, highlight.keys.filter { highlight[$0] != nil }.max() ?? 0) : 0 }

    func move(_ delta: Int) {
        let level = keyLevel
        let list = column(level).filter { query.isEmpty ? $0.selectable : true }
        guard !list.isEmpty else { return }
        let current = highlight[level].flatMap { id in list.firstIndex { $0.id == id } }
        let next = current.map { ($0 + delta + list.count) % list.count } ?? (delta > 0 ? 0 : list.count - 1)
        highlight[level] = list[next].id
        if query.isEmpty { trim(to: level) }
    }

    func openHighlighted() {
        let level = keyLevel
        guard query.isEmpty, let id = highlight[level], let i = item(id), i.kind == .sub, i.enabled else { return }
        withAnimation(Motion.easeOut) { path = Array(path.prefix(level)) + [id] }
        highlight[level + 1] = i.children.first { $0.selectable }?.id
    }

    func back() -> Bool {
        let level = keyLevel
        guard level > 0 else { return false }
        highlight[level] = nil
        trim(to: level - 1)
        return true
    }

    /// Runs the highlighted row, or the first search result.
    func runHighlighted() {
        let level = keyLevel
        if !query.isEmpty {
            let list = results.map(\.item)
            if let i = list.first(where: { $0.id == highlight[0] }) ?? list.first { run(i) }
            return
        }
        guard let id = highlight[level], let i = item(id) else { return }
        if i.kind == .sub { openHighlighted() } else { run(i) }
    }

    func run(_ item: MenuItem) {
        guard item.enabled, let action = item.action else { return }
        if item.kind == .action || item.kind == .check { Tips.shared.clicked(id: item.id, label: item.label, shortcut: item.shortcut) }
        if item.keepOpen {
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
        } else {
            close()
            DispatchQueue.main.async { action() }
        }
    }

    /// Re-reads live state while open, keeping what's highlighted and open.
    func refresh() {
        items = source()
    }
}

// MARK: - Controller

/// Opens and closes the menu under the status item, like a native menu: on mouse down, closed by a
/// click elsewhere, Esc, or picking something.
final class StatusMenu: NSObject, NSWindowDelegate {
    static let shared = StatusMenu()

    weak var button: NSStatusBarButton?
    let model = MenuModel()
    private var panel: OuchPanel?
    private let dismiss = DismissMonitor()
    private static let margin: CGFloat = 26

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard let button, let bw = button.window, !isOpen else { return }
        let screen = bw.screen ?? NSScreen.main ?? NSScreen.screens[0]
        model.reset()
        model.rebuild()
        model.close = { [weak self] in self?.close() }

        // Room for the root column and two levels of submenus on whichever side has space.
        let b = bw.frame, v = screen.visibleFrame, m = Self.margin
        let subs = 2 * (Theme.submenuWidth + 48)
        let left = min(max(b.minX, v.minX + 8), v.maxX - Theme.menuWidth - 8)
        model.opensLeft = left + Theme.menuWidth + subs > v.maxX - 8
        let width = Theme.menuWidth + subs + 2 * m
        let x = model.opensLeft ? left - subs - m : left - m
        let top = b.minY - 4 + m / 4
        let height = min(top - v.minY, 820)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        let rootX = model.opensLeft ? subs + m : m

        let p = panel ?? makePanel()
        panel = p
        p.contentView = OuchHostingView(rootView: MenuRoot(model: model, rootX: rootX, top: m / 4,
                                                         size: frame.size))
        p.setFrame(frame, display: true)
        p.makeKeyAndOrderFront(nil)
        button.highlight(true)
        DispatchQueue.main.async { withAnimation(Motion.easeOut) { self.model.appeared = true } }
        installMonitors()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        dismiss.stop()
        button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.contentView = nil
            self?.model.reset()
        })
    }

    /// Live state changed (tiling, a window moved): refresh the rows if open.
    func refreshIfOpen() { if isOpen { model.refresh() } }

    private func makePanel() -> OuchPanel {
        let p = OuchPanel(role: .menu)
        p.onClose = { [weak self] in self?.close() } // ⌘W; Esc and ⌘Q are the menu's own keys
        p.delegate = self
        return p
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    /// Clicks in other apps, and in our own windows outside the menu, close it; the status item toggles by itself.
    private func installMonitors() {
        dismiss.start(keeps: { [weak self] w in w === self?.panel || w === self?.button?.window },
                      key: { [weak self] e in
                          guard let self, panel?.isKeyWindow == true else { return false }
                          return key(e)
                      },
                      close: { [weak self] in self?.close() })
    }

    /// Menu keys: ↑↓ move, → opens, ← and Esc go back, ↩ runs; ⌘, ⌘/ ⌘Q work as shown (⌘Q quits, as the
    /// Quit row says). Everything else types into the search field.
    private func key(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd) {
        case (126, _): model.move(-1)
        case (125, _): model.move(1)
        case (124, false) where model.query.isEmpty: model.openHighlighted()
        case (123, false) where model.query.isEmpty: _ = model.back()
        case (36, _), (76, _): model.runHighlighted()
        case (53, _):
            if !model.query.isEmpty { model.query = "" } else if !model.back() { close() }
        case (43, true): close(); SettingsWindow.shared.show(pane: nil)
        case (44, true): close(); SettingsWindow.shared.show(pane: .shortcuts, map: true)
        case (12, true): NSApp.terminate(nil)
        default: return false
        }
        return true
    }
}

// MARK: - Views

private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
private struct ColumnHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
}

struct MenuRoot: View {
    @ObservedObject var model: MenuModel
    let rootX: CGFloat
    let top: CGFloat
    let size: CGSize
    var rootWidth: CGFloat = Theme.menuWidth
    /// Hangs the root column up from the bottom of the panel: a pop-up near the bottom of the screen.
    var fromBottom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A click beside the columns closes the menu, like a click anywhere else.
            Color.clear.contentShape(Rectangle()).onTapGesture { model.close() }
            column(0, width: rootWidth)
                .padding(.leading, rootX).padding(.top, fromBottom ? 0 : top).padding(.bottom, fromBottom ? top : 0)
                .frame(height: fromBottom ? size.height : nil, alignment: .bottom)
                .scaleEffect(model.appeared || reduceMotion ? 1 : 0.97, anchor: fromBottom ? .bottom : .top)
                .opacity(model.appeared ? 1 : 0)
            ForEach(Array(model.path.enumerated()), id: \.element) { i, id in
                if let parent = model.item(id), let row = model.rowFrames[id] {
                    let level = i + 1
                    let h = model.columnHeights[level] ?? 0
                    let y = max(top, min(row.minY - 4, size.height - h - 30))
                    let x = model.opensLeft ? row.minX - 4 - parent.width - 2 : row.maxX + 4 + 2
                    column(level, width: parent.width)
                        .padding(.leading, x).padding(.top, y)
                        .transition(.opacity.combined(with: .offset(x: model.opensLeft ? 4 : -4)))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: "menu")
        .onPreferenceChange(RowFrameKey.self) { f in if f != model.rowFrames { model.rowFrames = f } }
        .onPreferenceChange(ColumnHeightKey.self) { h in if h != model.columnHeights { model.columnHeights = h } }
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    private func column(_ level: Int, width: CGFloat) -> some View {
        MenuColumn(model: model, level: level)
            .frame(width: width)
            .surface(.md, glass: true)
            .background(GeometryReader { g in
                Color.clear.preference(key: ColumnHeightKey.self, value: [level: g.size.height])
            })
            .onHover { if $0 { model.enterColumn(level) } }
    }
}

private struct MenuColumn: View {
    @ObservedObject var model: MenuModel
    let level: Int
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if level == 0 && model.searchable {
                OSearchField(placeholder: "Search commands…", text: $model.query, focus: $searchFocused) {
                    model.runHighlighted()
                }
                .frame(height: 38)
                .onAppear { DispatchQueue.main.async { searchFocused = true } }
                .onChange(of: model.query) { _, q in
                    model.path = []
                    model.highlight = q.isEmpty ? [:] : [0: model.results.first?.item.id ?? ""]
                }
            }
            if level == 0 && !model.query.isEmpty {
                let results = model.results
                if results.isEmpty {
                    Text("No commands match").font(Theme.body(12.5)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(results, id: \.item.id) { r in
                                MenuRowView(model: model, item: r.item, level: 0, crumb: r.crumb)
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let rows = model.column(level).filter { !$0.hidden }
                if rows.count > 16 { // a long list, such as running apps, scrolls
                    ScrollView { VStack(spacing: 0) { ForEach(rows) { i in row(i) } } }
                        .frame(maxHeight: 480).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(rows) { i in row(i) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ i: MenuItem) -> some View {
        switch i.kind {
        case .separator:
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 4)
        case .label:
            HStack(spacing: 6) {
                Text(i.label).oneLine()
                Spacer(minLength: 4)
                if !i.shortcut.isEmpty { Text(i.shortcut.joined()).font(Theme.keys(12, .medium)).tracking(1) }
            }
            .font(Theme.body(11.5, .medium)).foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
        case .essentials:
            EssentialsRow(model: model, enabled: i.enabled)
        case .workspaces:
            let s = WindowManager.shared.workspaceSummary()
            let highest = s.all.compactMap { Int($0.name) }.max() ?? 0
            WorkspaceStrip(names: (1...max(9, min(highest, 10))).map(String.init), current: s.current,
                           occupied: Set(s.all.filter { $0.windows > 0 }.map(\.name))) { n in
                WindowManager.shared.showWorkspace(n)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.refresh() }
            }
            .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 8)
        case .layoutPicker:
            let current = WindowManager.shared.menuBarState()?.layout
            LayoutPicker(layouts: Layout.allCases, selection: current, columns: 4) { l in
                WindowManager.shared.dispatch("layout", l.rawValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { model.close() }
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
        case .attention:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(i.label).font(Theme.body(13, .medium)).oneLine()
                Spacer(minLength: 4)
                OButton("Grant Access", variant: .primary, size: .sm) { model.run(i) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        default:
            MenuRowView(model: model, item: i, level: level)
        }
    }
}

/// A dot in `accent`: a shape only, always beside a word that says what's waiting.
struct NotificationDot: View {
    var body: some View {
        Circle().fill(Theme.accent).frame(width: 6, height: 6)
            .overlay(Circle().strokeBorder(Theme.surfaceRaised, lineWidth: 1).padding(-1))
            .accessibilityHidden(true)
    }
}

/// The four square toggles at the top: Tiling, Float, Fullscreen, Retile.
private struct EssentialsRow: View {
    @ObservedObject var model: MenuModel
    let enabled: Bool

    var body: some View {
        let wm = WindowManager.shared
        let f = wm.focusedWindowState()
        let keys = ShortcutIndex()
        HStack(spacing: 4) {
            EssentialTile(title: "Tiling", label: "Tiling", symbol: "rectangle.split.3x1", offSymbol: "rectangle.on.rectangle",
                          isOn: wm.tilingEnabled, shortcut: keys.keys("toggletiling")) { act { wm.toggleTiling() } }
            EssentialTile(title: "Float", label: "Float window", symbol: "macwindow.on.rectangle", offSymbol: "macwindow",
                          isOn: f?.floating == true,
                          shortcut: keys.keys("togglefloating")) { act { wm.dispatch("togglefloating", "") } }
                .disabled(f == nil)
            EssentialTile(title: "Fullscreen", label: "Fullscreen", symbol: "arrow.down.right.and.arrow.up.left",
                          offSymbol: "arrow.up.left.and.arrow.down.right", isOn: f?.fullscreen == true,
                          shortcut: keys.keys("fullscreen")) { act { wm.dispatch("fullscreen", "") } }
                .disabled(f == nil)
            EssentialTile(title: "Retile", label: "Retile windows", symbol: "arrow.triangle.2.circlepath", shortcut: keys.keys("retile"), rotates: true) {
                act { wm.dispatch("retile", "") }
            }
        }
        .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 6)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    /// Toggles change state right away, so the tile swaps at once; a second look catches anything that settles later.
    private func act(_ f: () -> Void) {
        f()
        model.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.refresh() }
    }
}

private struct MenuRowView: View {
    @ObservedObject var model: MenuModel
    let item: MenuItem
    let level: Int
    var crumb: String? = nil
    @StateObject private var spins = Flag()

    var body: some View {
        let hi = model.highlight[level] == item.id
        let open = model.path.count > level && model.path[level] == item.id
        let muted: Color = Theme.inkMuted
        OMenuRow(highlighted: hi, open: open, danger: item.danger) {
            if item.kind == .sub {
                withAnimation(Motion.easeOut) { model.path = Array(model.path.prefix(level)) + [item.id] }
            } else {
                if item.rotates { spins.on.toggle() }
                model.run(item)
            }
        } lead: {
            lead(hi: hi, muted: muted)
        } label: {
            if item.kind == .footer {
                Text("Ouch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .textStyle(.caption).foregroundStyle(muted).oneLine()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // The name wins over the value beside it: "Resume Tutorial…" stays whole, "Window mode" gives way.
                    Text(item.label).oneLine().layoutPriority(1)
                    if let crumb, !crumb.isEmpty {
                        Text(crumb).textStyle(.caption).foregroundStyle(muted).oneLine()
                    } else if let value = item.value {
                        Text(value).font(Theme.body(12.5)).foregroundStyle(muted).oneLine()
                    }
                }
                .layoutPriority(1)
            }
        } trailing: {
            if item.kind == .footer {
                // The power symbol goes with Quit, not with the version number.
                Image(systemName: "power").font(Theme.symbol(Theme.Icon.sm)).foregroundStyle(muted)
                Text(item.label).font(Theme.body(12.5)).oneLine()
            }
            if let n = item.badge {
                Text("\(n)").font(Theme.body(12, .medium)).monospacedDigit()
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(Theme.accentSoft))
            }
            if item.kind == .sub && crumb == nil {
                Image(systemName: "chevron.right").font(Theme.symbol(10, .semibold)).foregroundStyle(muted)
            } else if !item.shortcut.isEmpty {
                Text(item.shortcut.joined()).font(Theme.keys(13)).tracking(1).foregroundStyle(muted).oneLine().fixedSize()
            }
        }
        .disabled(!item.enabled)
        .opacity(item.enabled ? 1 : 0.45)
        .onHover { if $0 { model.hover(item, level: level) } else { model.unhover(item, level: level) } }
        .background(GeometryReader { g in
            Color.clear.preference(key: RowFrameKey.self, value: item.kind == .sub ? [item.id: g.frame(in: .named("menu"))] : [:])
        })
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(item.checked ? .isSelected : [])
    }

    @ViewBuilder private func lead(hi: Bool, muted: Color) -> some View {
        switch item.kind {
        case .check:
            Image(systemName: "checkmark").font(Theme.symbol(Theme.Icon.sm, .bold))
                .foregroundStyle(Theme.accentInk)
                .opacity(item.checked ? 1 : 0)
                .drawOnEffect(isActive: item.checked)
        case .radio:
            Circle().fill(Theme.accentInk).frame(width: 7, height: 7).opacity(item.checked ? 1 : 0)
        case .footer:
            Color.clear // keeps the version in line with the labels above
        default:
            if let image = item.image {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 16, height: 16)
            } else if let symbol = item.symbol {
                let image = Image(systemName: symbol).font(Theme.symbol()).foregroundStyle(muted)
                Group { if item.rotates { image.rotateEffect(value: spins.on) } else { image } }
                    .overlay(alignment: .topTrailing) { if item.dot { NotificationDot().offset(x: 3, y: -2) } }
            }
        }
    }
}
