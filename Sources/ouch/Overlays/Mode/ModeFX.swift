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

    func setActive(_ on: Bool) {
        setActive(on, style: style)
    }

    private func setActive(_ on: Bool, style: Style) {
        guard on != model.active else { return }
        hideWork?.cancel()
        if on {
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
            for (i, s) in Style.allCases.filter({ $0 != .none }).enumerated() {
                schedule(Double(i) * 2.6) { [weak self] in self?.preview(s) }
            }
        case let name? where Style(rawValue: name) != nil:
            preview(Style(rawValue: name)!)
        default:
            Log.info("modefx: styles are \(Style.allCases.map(\.rawValue).joined(separator: ", ")), or all")
        }
    }

    private func preview(_ s: Style) {
        setActive(false)
        hideWork?.cancel()
        HUD.shared.show(s.rawValue.capitalized, on: NSScreen.main)
        schedule(0.05) { [weak self] in self?.setActive(true, style: s) }
        schedule(1.9) { [weak self] in
            if Hotkeys.shared.submap.isEmpty { self?.setActive(false) }
        }
    }

    private func schedule(_ delay: Double, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        demo.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func layoutPanels() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            let p = panels[id] ?? makePanel(screen)
            panels[id] = p
            if let host = p.contentView as? NSHostingView<ModeFXView> { host.rootView = view(for: screen) }
            p.setFrame(screen.frame, display: false)
            p.orderFrontRegardless()
        }
        for (id, p) in panels where !seen.contains(id) {
            p.orderOut(nil)
            panels[id] = nil
        }
    }

    private func makePanel(_ screen: NSScreen) -> NSPanel {
        let p = OuchPanel(role: .fullscreenFX, frame: screen.frame)
        p.contentView = NSHostingView(rootView: view(for: screen))
        return p
    }

    private func view(for screen: NSScreen) -> ModeFXView {
        let shape = ScreenShape.of(screen)
        return ModeFXView(model: model, radius: shape.topRadius, origin: screen.frame.origin,
                          notchHalfWidth: shape.notchHalfWidth, notchHeight: shape.notchHeight, topInset: shape.topInset)
    }
}
