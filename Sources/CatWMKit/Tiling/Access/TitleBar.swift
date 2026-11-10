import AppKit
import CoreGraphics

package struct TitleBar: Equatable {
    package enum Kind: Equatable {
        case standard
        case unifiedToolbar
        case fullSizeContent
        case none
    }

    package static let reach: CGFloat = 96

    package let kind: Kind
    package let clearTop: CGFloat?
    package let lights: CGRect?

    package init(lights: CGRect?, contentTop: CGFloat?, controlTop: CGFloat?) {
        self.lights = lights
        if let lights {
            if let controlTop, controlTop < lights.maxY {
                kind = .unifiedToolbar
            } else if contentTop.map({ $0 < lights.maxY }) ?? true {
                kind = .fullSizeContent
            } else {
                kind = .standard
            }
        } else {
            kind = .none
        }
        if let controlTop {
            clearTop = max(0, min(controlTop, Self.reach))
        } else {
            clearTop = kind == .standard ? Self.reach : nil
        }
    }
}

package final class TitleBarCache {
    private var entries: [CGWindowID: (width: CGFloat, bar: TitleBar)] = [:]

    package init() {}

    package func titleBar(of window: Window, on scanner: WindowScanner, _ done: @escaping (TitleBar?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let id = window.id, width = window.cachedFrame.width, element = window.element
        if let entry = entries[id], entry.width == width { return done(entry.bar) }
        guard !AXStalls.shared.isStalled(window.pid) else { return done(nil) }
        scanner.run(window.pid) { [weak self] in
            let bar = TitleBar.read(element)
            DispatchQueue.main.async {
                if let bar { self?.entries[id] = (width, bar) }
                done(bar)
            }
        }
    }

    package func forget(_ id: CGWindowID) {
        entries[id] = nil
    }
}
