import AppKit
import CatWMKit

@MainActor final class AppIcons: ObservableObject {
    static let shared = AppIcons()
    private nonisolated static let side: CGFloat = 24
    private nonisolated static let scale: CGFloat = 2

    var onLoad: (() -> Void)?
    private var cache: [pid_t: NSImage] = [:]
    private var loading: Set<pid_t> = []
    private let placeholder = NSImage(size: CGSize(width: side, height: side))

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        guard loading.insert(pid).inserted else { return nil }
        let url = NSRunningApplication(processIdentifier: pid)?.bundleURL
        Task.detached(priority: .utility) { [weak self] in
            let image = Self.render(url)
            await self?.finish(pid, image)
        }
        return nil
    }

    func iconOrGeneric(for pid: pid_t) -> NSImage {
        icon(for: pid) ?? placeholder
    }

    func prune(keeping pids: Set<pid_t>) {
        cache = cache.filter { pids.contains($0.key) || NSRunningApplication(processIdentifier: $0.key) != nil }
    }

    private func finish(_ pid: pid_t, _ image: CGImage?) {
        loading.remove(pid)
        let size = CGSize(width: Self.side, height: Self.side)
        cache[pid] = image.map { NSImage(cgImage: $0, size: size) } ?? placeholder
        objectWillChange.send()
        onLoad?()
    }

    private nonisolated static func render(_ url: URL?) -> CGImage? {
        let pixels = Int(side * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let workspace = NSWorkspace.shared
        let icon = url.map { workspace.icon(forFile: $0.path) } ?? workspace.icon(for: .application)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
