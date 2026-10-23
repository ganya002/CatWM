import AppKit

final class TitleBarCache {
    private var entries: [CGWindowID: (width: CGFloat, bar: TitleBar)] = [:]

    func titleBar(of window: Window, on scanner: WindowScanner, _ done: @escaping (TitleBar?) -> Void) {
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

    func forget(_ id: CGWindowID) {
        entries[id] = nil
    }
}
