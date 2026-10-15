// BugReport: the bug report panel, its model and views.
import AppKit
import SwiftUI

// MARK: - Panel

/// The bug report card: hand it to one of the user's agents, or write it here and send it. After a
/// crash it opens on its own with the crash report attached.
final class BugReportPanel: NSObject, NSWindowDelegate {
    static let shared = BugReportPanel()
    private var panel: NSPanel?
    private var host: NSHostingView<BugReportView>?
    private let model = BugReportModel()

    /// A new report, from the menu or (with `crash`) after a crash.
    func show(crash: URL? = nil) {
        // An open report the user hasn't touched yet just comes forward, unless a crash replaces it.
        if panel?.isVisible == true, crash == nil || model.crash != nil { return front() }
        discardUnused()
        guard let report = BugReport.create(crash: crash) else {
            HUD.shared.warn("Couldn't create a bug report", on: nil)
            return
        }
        model.reset(report: report, crash: crash.flatMap(CrashSummary.init), text: "")
        open()
    }

    /// An `ouch://report?id=…` link: an agent finished report.md and hands it back for sending.
    func handle(_ url: URL) {
        guard url.host == "report",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              let report = BugReport.existing(id: id)
        else { return Log.info("bug report: ignored link \(url.absoluteString)") }
        if model.report?.id != report.id { discardUnused() }
        let text = (try? String(contentsOf: report.report, encoding: .utf8)) ?? ""
        model.reset(report: report, crash: report.crash.flatMap(CrashSummary.init), text: text)
        model.fromAgent = !text.isEmpty
        open()
    }

    private func open() {
        Agents.detect { [weak self] agents in
            self?.model.agents = agents
            self?.fit()
        }
        model.send = { [weak self] in
            guard let self, let r = model.report, !model.sending else { return }
            model.sending = true
            model.failed = false
            ReportSender.send(r, text: model.text, crash: model.crash) { ok in
                self.model.sending = false
                guard ok else { return self.model.failed = true }
                self.model.sent = true
                self.close()
                if ReportSender.endpoint != nil { HUD.shared.show("Report sent", on: nil) }
            }
        }
        model.ask = { [weak self] agent in
            guard let self, let r = model.report else { return }
            agent.launch(r)
            withAnimation(Motion.easeOut) { self.model.asked = agent.id }
            DispatchQueue.main.async { self.fit() }
        }
        model.reveal = { [weak self] in
            guard let r = self?.model.report else { return }
            NSWorkspace.shared.activateFileViewerSelecting(r.attachments)
        }
        model.dismiss = { [weak self] in self?.close() }

        let p = panel ?? makePanel()
        panel = p
        fit()
        if !p.isVisible { p.center() }
        front()
    }

    /// The card's height follows its content (agents arrive late, a sent-back report needs more room);
    /// the top edge stays put.
    private func fit() {
        guard let p = panel, let host else { return }
        host.layoutSubtreeIfNeeded()
        // The measurement still counts the hidden title bar, which the content now ignores.
        var size = host.fittingSize
        size.height -= host.safeAreaInsets.top
        guard size.height > 0, p.contentLayoutRect.size != size else { return }
        var frame = p.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: p.frame.minX, y: p.frame.maxY - frame.height)
        p.setFrame(frame, display: true, animate: p.isVisible)
    }

    private func front() {
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) { discardUnused() }

    /// A report nobody wrote, sent or handed to an agent is just clutter.
    private func discardUnused() {
        guard let r = model.report, !model.sent, model.asked == nil,
              model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !FileManager.default.fileExists(atPath: r.report.path) else { return }
        r.delete()
        model.report = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: BugReportView.width, height: 10),
                        styleMask: [.titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        // A unified toolbar makes the title bar as tall as the header row, so the close button sits
        // centred beside the title instead of above it.
        p.toolbar = NSToolbar()
        p.toolbarStyle = .unified
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        let host = NSHostingView(rootView: BugReportView(model: model))
        host.sizingOptions = [.intrinsicContentSize] // measured by fittingSize; fit() applies it
        self.host = host
        if #available(macOS 26.0, *) {
            p.isOpaque = false
            p.backgroundColor = .clear
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.Radius.xl
            glass.contentView = host
            p.contentView = glass
        } else {
            p.backgroundColor = Theme.ns(\.surfaceRaised)
            p.contentView = host
        }
        return p
    }
}

// MARK: - Model

final class BugReportModel: ObservableObject {
    @Published var report: BugReport?
    @Published var crash: CrashSummary?
    @Published var agents: [Agent] = []
    @Published var text = ""
    /// The agent last asked, so its icon can say so.
    @Published var asked: Agent.ID?
    /// report.md came back from an agent.
    @Published var fromAgent = false
    @Published var sending = false
    /// The last send didn't go through; the button offers to try again.
    @Published var failed = false
    var sent = false

    var send: () -> Void = {}
    var ask: (Agent) -> Void = { _ in }
    var reveal: () -> Void = {}
    var dismiss: () -> Void = {}

    func reset(report: BugReport, crash: CrashSummary?, text: String) {
        self.report = report
        self.crash = crash
        self.text = text
        asked = nil
        fromAgent = false
        sending = false
        failed = false
        sent = false
    }

    var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Views

struct BugReportView: View {
    static let width: CGFloat = 440
    /// The unified title bar's height; the header row shares it with the close button.
    private static let titleBar: CGFloat = 52
    @ObservedObject var model: BugReportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Only a crash gets a badge; a plain report is just the app.
                if model.crash != nil {
                    BadgedAppIcon(badge: "exclamationmark.triangle.fill", color: Theme.warning, size: 30)
                } else {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30).accessibilityHidden(true)
                }
                Text(title).font(Theme.body(22)).oneLine()
                    .tooltip(model.crash?.headline ?? "")
            }
            .frame(height: Self.titleBar)
            .padding(.leading, 44 - 32) // clear of the close button
            if !model.fromAgent, !model.agents.isEmpty {
                Text("Ask your agent").font(Theme.body(12, .medium)).foregroundStyle(Theme.inkMuted).oneLine()
                    .padding(.top, 12).padding(.bottom, 8)
                agents
            }
            editor.padding(.top, 20)
            HStack(spacing: 8) {
                OIconButton(symbol: "paperclip", label: "Show attached files", action: model.reveal)
                Spacer(minLength: 0)
                OButton(model.crash != nil ? "Not now" : "Cancel", variant: .ghost, action: model.dismiss)
                    .keyboardShortcut(.cancelAction)
                OButton(sendTitle, variant: .primary, size: .lg, shortcut: model.sending ? [] : ["⌘", "↩"], action: model.send)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSend || model.sending)
            }
            .padding(.top, 20)
        }
        .padding(EdgeInsets(top: 0, leading: 32, bottom: 28, trailing: 32))
        .frame(width: Self.width, alignment: .leading)
        .ignoresSafeArea() // the header row lives in the title bar, beside the close button
    }

    private var sendTitle: String {
        if model.sending { return "Sending…" }
        if model.failed { return "Try again" }
        return ReportSender.canSend ? "Send" : "Copy"
    }

    private var title: String {
        if model.fromAgent { return "Ready to send" }
        return model.crash != nil ? "Ouch crashed" : "Report a bug"
    }

    /// One icon per maker, on one row. Names are in the tooltips; the rest go under "more".
    private var agents: some View {
        let groups = AgentGroup.make(model.agents)
        let fits = groups.count <= Self.maxTiles ? groups.count : Self.maxTiles - 1
        return HStack(spacing: 10) {
            ForEach(groups.prefix(fits)) { group in
                AgentTile(group: group, asked: group.agents.contains { $0.id == model.asked }, ask: model.ask)
            }
            if fits < groups.count {
                MoreAgents(groups: Array(groups.dropFirst(fits)), ask: model.ask)
            }
        }
    }

    private static let maxTiles = 6

    private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        return TextEditor(text: $model.text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(height: model.fromAgent ? 220 : 90)
            .background(shape.fill(Theme.well))
            .overlay(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("Or write what happened")
                        .font(Theme.body(13)).foregroundStyle(Theme.inkFaint).oneLine()
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Bug report")
    }
}

/// A maker's icon. With both an app and a command-line agent, clicking asks which.
private struct AgentTile: View {
    let group: AgentGroup
    let asked: Bool
    let ask: (Agent) -> Void

    var body: some View {
        Group {
            if group.agents.count == 1 {
                Button { ask(group.agents[0]) } label: { icon }
                    .buttonStyle(PressScale())
            } else {
                let agents = group.agents, ask = ask
                OMenuButton(items: {
                    agents.map { agent in
                        MenuItem(id: agent.id, label: agent.isCLI ? "Terminal" : agent.name, image: menuIcon(agent), action: { ask(agent) })
                    }
                }) { icon }
                    .fixedSize()
            }
        }
        .tooltip(group.name)
        .accessibilityLabel("Ask \(group.name)")
    }

    private var icon: some View {
        Image(nsImage: group.icon)
            .resizable().interpolation(.high)
            .frame(width: 48, height: 48)
            .overlay(alignment: .bottomTrailing) {
                if group.agents.allSatisfy(\.isCLI) { TerminalBadge() }
            }
            .overlay(alignment: .topTrailing) {
                if asked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.onAccent, Theme.accent)
                        .background(Circle().fill(Theme.surface).padding(1))
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Motion.spring, value: asked)
    }
}

/// The makers that didn't fit on the row, as a menu.
private struct MoreAgents: View {
    let groups: [AgentGroup]
    let ask: (Agent) -> Void

    var body: some View {
        let groups = groups, ask = ask
        OMenuButton(items: {
            groups.flatMap(\.agents).map { agent in
                MenuItem(id: agent.id, label: agent.name, image: menuIcon(agent), action: { ask(agent) })
            }
        }) {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.well))
        }
        .fixedSize()
        .tooltip("More agents")
        .accessibilityLabel("More agents")
    }
}

private struct TerminalBadge: View {
    var body: some View {
        Image(systemName: "apple.terminal.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Theme.ink))
            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 1.5))
            .offset(x: 2, y: 2)
    }
}

/// Menus draw images at their own size, so hand them a small copy; Terminal for command-line agents.
private func menuIcon(_ agent: Agent) -> NSImage {
    let source = agent.isCLI
        ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal").map { NSWorkspace.shared.icon(forFile: $0.path) } ?? agent.icon
        : agent.icon
    let small = source.copy() as! NSImage
    small.size = NSSize(width: 16, height: 16)
    return small
}
