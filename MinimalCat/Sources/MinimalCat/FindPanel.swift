import AppKit
import MinimalCatCore
import SwiftUI

/// Type a few letters of a window or app name, then Return.
@MainActor
final class FindPanel {
    private let panel = FloatingPanel(takesKey: true)
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    func show(_ windows: [WindowInfo], icons: [WindowID: NSImage], choose: @escaping (WindowID) -> Void) {
        let model = FindModel(windows: windows, icons: icons)
        model.choose = { [weak self] id in
            self?.close()
            choose(id)
        }
        model.cancel = { [weak self] in self?.close() }
        NSApp.activate(ignoringOtherApps: true)
        panel.show(FindView(model: model), on: activeScreen(), at: .top)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 125: model.step(1); return nil
            case 126: model.step(-1); return nil
            case 36, 76: model.confirm(); return nil
            case 53: model.cancel?(); return nil
            default: return event
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        resignObserver.map(NotificationCenter.default.removeObserver)
        resignObserver = nil
        panel.orderOut(nil)
    }
}

@MainActor
final class FindModel: ObservableObject {
    let windows: [WindowInfo]
    let icons: [WindowID: NSImage]
    @Published var query = "" { didSet { selected = 0 } }
    @Published var selected = 0
    var choose: ((WindowID) -> Void)?
    var cancel: (() -> Void)?

    init(windows: [WindowInfo], icons: [WindowID: NSImage]) {
        self.windows = windows
        self.icons = icons
    }

    var results: [WindowInfo] { Array(Find.rank(query, windows).prefix(8)) }

    func step(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
    }

    func confirm() {
        guard results.indices.contains(selected) else { return }
        choose?(results[selected].id)
    }
}

struct FindView: View {
    @ObservedObject var model: FindModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                TextField("Find a window", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .accessibilityLabel("Find a window")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            if !model.results.isEmpty { Divider().overlay(Theme.hairline) }
            VStack(spacing: 2) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, window in
                    row(window, selected: index == model.selected)
                        .onTapGesture { model.choose?(window.id) }
                }
            }
            .padding(model.results.isEmpty ? 0 : 6)
        }
        .frame(width: 520)
        .floatingCard(radius: 18)
        .padding(40)
        .onAppear { focused = true }
    }

    private func row(_ window: WindowInfo, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon = model.icons[window.id] {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            }
            Text(window.name).font(Theme.body).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(window.app).font(Theme.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
