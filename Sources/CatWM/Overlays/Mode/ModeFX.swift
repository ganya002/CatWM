import AppKit
import CatWMKit
import SwiftUI

final class ModeFX {
    static let shared = ModeFX()

    var style: ModeEffect = .draw
    private let model = ModeFXModel()
    private var panels: [CGDirectDisplayID: (panel: NSPanel, screen: ModeFXScreen)] = [:]
    private var isOn = false
    private var hideWork: DispatchWorkItem?
    private var demo: [DispatchWorkItem] = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.reshape()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.reshape() }
            },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                if self?.model.active == true { self?.layoutPanels() }
            }
        ]
    }

    private func reshape() {
        guard model.active else { return }
        for screen in NSScreen.screens {
            if let id = screen.displayID { panels[id]?.screen.update(screen) }
        }
    }

    func setActive(_ active: Bool) {
        setActive(active, style: style)
    }

    private func setActive(_ active: Bool, style: ModeEffect) {
        guard active != isOn, !active || style != .none else { return }
        isOn = active
        hideWork?.cancel()
        if active {
            model.style = style
            layoutPanels()
            model.cursor = NSEvent.mouseLocation
            PerfMonitor.shared.track("ui:modefx-\(style)", for: 0.6)
            DispatchQueue.main.async { [weak self] in
                guard let self, isOn else { return }
                model.active = true
                model.enters += 1
            }
        } else {
            model.active = false
            let work = DispatchWorkItem { [weak self] in self?.panels.values.forEach { $0.panel.orderOut(nil) } }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    func command(_ args: [String]) {
        demo.forEach { $0.cancel() }
        demo = []
        switch args.first?.lowercased() {
        case "all":
            for (i, choice) in ModeEffect.allCases.filter({ $0 != .none }).enumerated() {
                schedule(Double(i) * 2.6) { [weak self] in self?.preview(choice) }
            }
        case let name?:
            if let choice = ModeEffect(rawValue: name) {
                preview(choice)
            } else {
                logStyles()
            }
        default:
            logStyles()
        }
    }

    private func logStyles() {
        Log.info("modefx: styles are \(ModeEffect.allCases.map(\.rawValue).joined(separator: ", ")), or all")
    }

    private func preview(_ choice: ModeEffect) {
        setActive(false)
        hideWork?.cancel()
        HUD.shared.show(choice.rawValue.capitalized, on: NSScreen.main)
        schedule(0.05) { [weak self] in self?.setActive(true, style: choice) }
        schedule(1.9) { [weak self] in
            if Hotkeys.shared.submap.isEmpty { self?.setActive(false) }
        }
    }

    private func schedule(_ delay: Double, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        demo.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func layoutPanels() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            let entry = panels[id] ?? makePanel(screen)
            panels[id] = entry
            entry.screen.update(screen)
            if entry.panel.frame != screen.frame { entry.panel.setFrame(screen.frame, display: false) }
            if !entry.panel.isVisible {
                entry.panel.orderFrontRegardless()
                OverlaySpace.add(entry.panel)
            }
        }
        for (id, entry) in panels where !seen.contains(id) {
            entry.panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func makePanel(_ screen: NSScreen) -> (panel: NSPanel, screen: ModeFXScreen) {
        let state = ModeFXScreen(screen)
        let panel = CatWMPanel(role: .fullscreenFX, frame: screen.frame)
        panel.contentView = NSHostingView(rootView: ModeFXView(model: model, screen: state))
        return (panel, state)
    }
}

final class ModeFXModel: ObservableObject {
    @Published var active = false
    @Published var enters = 0
    @Published var style: ModeEffect = .draw
    @Published var color = Theme.accent
    var cursor: CGPoint = .zero
}

final class ModeFXScreen: ObservableObject {
    @Published private(set) var shape: ScreenShape
    @Published private(set) var origin: CGPoint

    init(_ screen: NSScreen) {
        shape = .of(screen)
        origin = screen.frame.origin
    }

    func update(_ screen: NSScreen) {
        let next = ScreenShape.of(screen)
        if next != shape { shape = next }
        if screen.frame.origin != origin { origin = screen.frame.origin }
    }
}
