import AppKit
import SwiftUI

final class ModeFX {
    static let shared = ModeFX()

    enum Style: String, CaseIterable {
        case draw, ripple, corners, none

        var title: String {
            switch self {
            case .draw: "Draw"
            case .ripple: "Ripple"
            case .corners: "Corners"
            case .none: "None"
            }
        }
    }

    var style: Style = .draw
    private let model = ModeFXModel()
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var hideWork: DispatchWorkItem?
    private var demo: [DispatchWorkItem] = []

    func setActive(_ active: Bool) {
        setActive(active, style: style)
    }

    private func setActive(_ active: Bool, style: Style) {
        guard active != model.active else { return }
        hideWork?.cancel()
        if active {
            guard style != .none else { return }
            model.style = style
            layoutPanels()
            model.cursor = NSEvent.mouseLocation
            model.active = true
            PerfMonitor.track("ui:modefx-\(style)", for: 0.6)
            DispatchQueue.main.async { [weak self] in self?.model.enters += 1 }
        } else {
            model.active = false
            let work = DispatchWorkItem { [weak self] in self?.panels.values.forEach { $0.orderOut(nil) } }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    func command(_ args: [String]) {
        demo.forEach { $0.cancel() }
        demo = []
        switch args.first?.lowercased() {
        case "all":
            for (i, choice) in Style.allCases.filter({ $0 != .none }).enumerated() {
                schedule(Double(i) * 2.6) { [weak self] in self?.preview(choice) }
            }
        case let name?:
            if let choice = Style(rawValue: name) {
                preview(choice)
            } else {
                logStyles()
            }
        default:
            logStyles()
        }
    }

    private func logStyles() {
        Log.info("modefx: styles are \(Style.allCases.map(\.rawValue).joined(separator: ", ")), or all")
    }

    private func preview(_ choice: Style) {
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
            let panel = panels[id] ?? makePanel(screen)
            panels[id] = panel
            if let host = panel.contentView as? NSHostingView<ModeFXView> { host.rootView = view(for: screen) }
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
        }
        for (id, panel) in panels where !seen.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func makePanel(_ screen: NSScreen) -> NSPanel {
        let panel = OuchPanel(role: .fullscreenFX, frame: screen.frame)
        panel.contentView = NSHostingView(rootView: view(for: screen))
        return panel
    }

    private func view(for screen: NSScreen) -> ModeFXView {
        let shape = ScreenShape.of(screen)
        return ModeFXView(model: model, radius: shape.topRadius, origin: screen.frame.origin,
                          notchHalfWidth: shape.notchHalfWidth, notchHeight: shape.notchHeight,
                          topInset: shape.topInset)
    }
}
