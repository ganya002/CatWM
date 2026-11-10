import AppKit
import ScreenCaptureKit

@MainActor package final class DesktopWallpaperCover {
    package static let shared = DesktopWallpaperCover()
    private var windows: [CGWindowID: SCWindow] = [:]
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]
    private var metadata: Task<Void, Never>?
    private var warmed = false
    private var pending: Pending?
    private var spare: CatWMPanel?
    private var active: [UInt64: Lease] = [:]
    private var sources: [String: (space: UInt64, window: CGWindowID)] = [:]
    private var cached: [String: (space: UInt64, image: CGImage)] = [:]
    private var recapture: Task<Void, Never>?
    private var switches: NSObjectProtocol?

    private init() {
        Log.debug("native workspaces: wallpaper capture permission: \(Permission.screenRecording.isGranted)")
    }

    private enum Capture { case waiting, finished(CGImage?) }

    private final class Pending {
        package let screen: Screen
        package let source: UInt64
        package let target: UInt64
        package let panel: CatWMPanel
        package let image: Task<CGImage?, Never>
        package let started = CACurrentMediaTime()
        package var capture = Capture.waiting

        package init(screen: Screen, source: UInt64, target: UInt64, panel: CatWMPanel, image: Task<CGImage?, Never>) {
            self.screen = screen; self.source = source; self.target = target
            self.panel = panel; self.image = image
        }
    }

    package func prepare() {
        guard !warmed, Permission.screenRecording.isGranted else { return }
        warmed = true
        if let frame = Screen.all().first?.nsScreen?.frame {
            spare = DesktopMenuBarCover.makePanel(
                frame: frame, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1))
        }
        switches = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in DesktopWallpaperCover.shared.rememberAfterSwitch() } }
        Task {
            await refresh()
            for screen in Screen.all() { await remember(on: screen) }
        }
    }

    private func rememberAfterSwitch() {
        recapture?.cancel()
        recapture = Task {
            guard await poll(2, every: 50_000_000, until: {
                Screen.all().allSatisfy { DesktopBridge.isIdle(display: $0.uuid) }
            }) else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return } // style-ok: no paint event
            for screen in Screen.all() where !Task.isCancelled { await remember(on: screen) }
        }
    }

    private func remember(on screen: Screen) async {
        let space = Spaces.current(display: screen.uuid)
        guard Permission.screenRecording.isGranted, active[space] == nil, pending == nil,
              let window = wallpaperWindow(on: screen, space: space),
              let image = await image(window: window, on: screen),
              !Task.isCancelled, Spaces.current(display: screen.uuid) == space else { return }
        cached[screen.uuid] = (space, image)
    }

    package func prepare(on screen: Screen, source: UInt64, target: UInt64, fresh: Bool) {
        guard fresh else { discard(); return }
        if let pending, pending.source == source, pending.target == target { return }
        discard()
        guard Permission.screenRecording.isGranted else {
            Log.debug("native workspaces: wallpaper preview unavailable without Screen Recording")
            return
        }
        guard Spaces.current(display: screen.uuid) == source else { return }
        let previous = active[source]?.visibleImage()
            ?? cached[screen.uuid].flatMap { $0.space == source ? $0.image : nil }
        let window = previous == nil ? wallpaperWindow(on: screen, space: source) : nil
        guard previous != nil || window != nil else { return }
        let image = Task<CGImage?, Never> {
            if let previous { return previous }
            guard let window else { return nil as CGImage? }
            return await self.image(window: window, on: screen)
        }
        let frame = screen.nsScreen?.frame ?? .zero
        let panel = spare ?? DesktopMenuBarCover.makePanel(
            frame: frame, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1))
        spare = nil
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.alphaValue = 1
        let next = Pending(screen: screen, source: source, target: target, panel: panel, image: image)
        pending = next
        Task { next.capture = .finished(await image.value) }
        Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return } // style-ok: drop an unused creation capture
            if pending === next { discard() }
        }
    }

    package func isReady(source: UInt64, target: UInt64) -> Bool {
        guard let pending, pending.source == source, pending.target == target,
              case .finished(let image) = pending.capture else { return false }
        return image != nil
    }

    package func present(source: UInt64, target: UInt64, while current: () -> Bool) async -> Lease? {
        guard let next = pending, next.source == source, next.target == target else { return nil }
        let budget = max(0, 0.1 - (CACurrentMediaTime() - next.started))
        let ready = await poll(budget, every: 1_000_000, while: {
            current() && pending === next && Spaces.current(display: next.screen.uuid) == source
        }, until: {
            if case .finished = next.capture { return true }
            return false
        })
        guard ready, case .finished(let image?) = next.capture, !Task.isCancelled else {
            Log.debug("native workspaces: wallpaper preview unavailable before motion")
            if pending === next { discard() }
            return nil
        }
        pending = nil
        if let frame = next.screen.nsScreen?.frame, next.panel.frame != frame {
            next.panel.setFrame(frame, display: false)
        }
        (next.panel.contentView as? NSImageView)?.image = NSImage(cgImage: image, size: next.panel.frame.size)
        next.panel.orderFrontRegardless()
        next.panel.displayIfNeeded()
        CATransaction.flush()
        let lease = Lease(owner: self, panel: next.panel, image: image, screen: next.screen, target: target)
        active[target] = lease
        Log.info("native workspaces: previous wallpaper cover on Desktop \(target)")
        return lease
    }

    package func withdraw(from space: UInt64) {
        if pending?.target == space { discard() }
        cached = cached.filter { $0.value.space != space }
        active[space]?.drop()
    }

    private func discard() {
        pending?.image.cancel()
        if let panel = pending?.panel { recycle(panel) }
        pending = nil
    }

    private func recycle(_ panel: CatWMPanel) {
        DesktopMenuBarNative.orderOut(CGWindowID(panel.windowNumber))
        panel.orderOut(nil)
        panel.alphaValue = 1
        (panel.contentView as? NSImageView)?.image = nil
        if spare == nil { spare = panel } else { panel.close() }
    }

    @MainActor package final class Lease {
        private let owner: DesktopWallpaperCover
        private let panel: CatWMPanel
        private let image: CGImage
        private let screen: Screen
        private let target: UInt64
        private var painted: CGImage?
        private var closed = false
        private var watch: Task<Void, Never>?
        private var navigation: NSObjectProtocol?

        package init(owner: DesktopWallpaperCover, panel: CatWMPanel, image: CGImage, screen: Screen, target: UInt64) {
            self.owner = owner; self.panel = panel; self.image = image; self.screen = screen; self.target = target
            navigation = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    if let self, self.watch != nil, Spaces.current(display: self.screen.uuid) != self.target {
                        self.drop()
                    }
                }
            }
        }

        package func end(shown: Bool, settings: NativeDesktopController.Settings) {
            guard shown else { drop(); return }
            guard watch == nil, !closed else { return }
            panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
            guard NativeSpaceMove.move(window: CGWindowID(panel.windowNumber), to: target) else {
                drop(); return
            }
            watch = Task {
                let limit = Task {
                    do {
                        try await Task.sleep(for: .seconds(1)) // style-ok: limit for a blocked wallpaper capture
                        try Task.checkCancellation()
                    } catch { return }
                    Log.info("native workspaces: wallpaper cover timed out on Desktop \(target)")
                    drop()
                }
                defer { limit.cancel(); drop() }
                var window: CGWindowID?
                let ready = await poll(1, while: { !closed && Spaces.current(display: screen.uuid) == target }, until: {
                    window = owner.wallpaperWindow(on: screen, space: target)
                    return window != nil
                })
                guard ready, let window else { return }
                while !closed, !Task.isCancelled, Spaces.current(display: screen.uuid) == target {
                    guard let frame = await owner.image(window: window, on: screen), !closed,
                          let visible = await owner.image(window: window, on: screen, background: true),
                          !closed, Spaces.current(display: screen.uuid) == target else { return }
                    if !DesktopWallpaperCover.matches(frame, visible) { continue }
                    painted = frame
                    owner.cached[screen.uuid] = (target, frame)
                    limit.cancel()
                    Log.info("native workspaces: wallpaper cover handoff on Desktop \(target)")
                    await fade(with: settings)
                    return
                }
            }
        }

        private func fade(with settings: NativeDesktopController.Settings) async {
            do {
                let fade = NativeDesktopController.Settings(
                    duration: settings.duration, curve: .easeOut, bounce: 0)
                let motion = DesktopMotion(screen: screen.nsScreen)
                try await motion.animate(from: panel.alphaValue, to: 0, with: fade) {
                    guard !self.closed, Spaces.current(display: self.screen.uuid) == self.target else {
                        throw CancellationError()
                    }
                    self.panel.alphaValue = $0
                }
            } catch is CancellationError { } catch {
                Log.info("native workspaces: wallpaper fade ended: \(error.localizedDescription)")
            }
        }

        package func visibleImage() -> CGImage {
            guard let painted, panel.alphaValue < 1 else { return image }
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.draw(painted, in: rect)
            context.setAlpha(panel.alphaValue)
            context.draw(image, in: rect)
            return context.makeImage() ?? image
        }

        package func drop() {
            guard !closed else { return }
            closed = true
            watch?.cancel()
            if let navigation { NSWorkspace.shared.notificationCenter.removeObserver(navigation) }
            navigation = nil
            owner.active[target] = nil
            owner.recycle(panel)
            Log.info("native workspaces: wallpaper cover retired on Desktop \(target)")
        }
    }
}

extension DesktopWallpaperCover {
    private func wallpaperWindow(on screen: Screen, space: UInt64) -> CGWindowID? {
        let level = CGWindowLevelForKey(.desktopWindow) - 1
        if let window = DesktopMenuBarNative.windows(on: space, levels: [level]).first(where: {
            $0.frame == screen.frame && Spaces.of(window: $0.id).contains(space)
        }) { return window.id }
        guard let catalog = Spaces.list(display: screen.uuid), let index = catalog.ids.firstIndex(of: space),
              !catalog.desktops.contains(index) else { return nil }
        if let source = sources[screen.uuid], source.space == space,
           let info = DesktopMenuBarNative.info(source.window), info.level == level,
           info.frame == screen.frame { return source.window }
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let found = list.compactMap { info -> CGWindowID? in
            guard info[kCGWindowLayer as String] as? Int == Int(level),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  CGRect(dictionaryRepresentation: bounds as CFDictionary) == screen.frame else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
        guard found.count == 1 else { return nil }
        sources[screen.uuid] = (space, found[0])
        return found[0]
    }

    private func refresh() async {
        if let metadata { await metadata.value; return }
        let task = Task {
            guard Permission.screenRecording.isGranted else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                displays = Dictionary(content.displays.map { ($0.displayID, $0) },
                                      uniquingKeysWith: { first, _ in first })
            } catch { Log.info("native workspaces: wallpaper metadata unavailable: \(error.localizedDescription)") }
        }
        metadata = task
        await task.value
        metadata = nil
    }

    private func image(window: CGWindowID, on screen: Screen,
                       size: CGSize? = nil, background: Bool = false) async -> CGImage? {
        guard Permission.screenRecording.isGranted else { return nil }
        if windows[window] == nil || displays[screen.id] == nil {
            await refresh()
        }
        guard let window = windows[window], let display = displays[screen.id] else { return nil }
        let filter: SCContentFilter
        if background {
            let layers = windows.values.filter { $0.windowLayer < Int(CGWindowLevelForKey(.desktopWindow)) }
            filter = SCContentFilter(display: display, including: layers)
        } else { filter = SCContentFilter(desktopIndependentWindow: window) }
        if #available(macOS 14.2, *) { filter.includeMenuBar = false }
        let config = SCStreamConfiguration()
        config.width = Int(size?.width ?? CGFloat(CGDisplayPixelsWide(screen.id)))
        config.height = Int(size?.height ?? CGFloat(CGDisplayPixelsHigh(screen.id)))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        if #available(macOS 14.2, *) {
            config.includeChildWindows = true
            config.ignoreShadowsDisplay = true
            config.ignoreShadowsSingleWindow = true
        }
        guard Permission.screenRecording.isGranted, !Task.isCancelled else { return nil }
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            Log.info("native workspaces: wallpaper capture unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    private static func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? bytes : nil
    }

    package static func matches(_ expected: CGImage, _ visible: CGImage) -> Bool {
        let width = 64, height = 40
        guard let reference = pixels(expected, width: width, height: height),
              let actual = pixels(visible, width: width, height: height) else { return false }
        var samples: [Int] = [], product = 0.0, square = 0.0
        for row in 2..<(height - 2) {
            for column in 1..<(width - 1) {
                let offset = (row * width + column) * 4
                guard reference[offset + 3] > 250, actual[offset + 3] > 250 else { return false }
                samples.append(offset)
                for channel in 0..<3 {
                    let value = Double(reference[offset + channel])
                    product += value * Double(actual[offset + channel]); square += value * value
                }
            }
        }
        let dim = square > 0 ? product / square : 1
        guard (0.2...1.25).contains(dim) else { return false }
        let matching = samples.filter { offset in
            (0..<3).reduce(0.0) { total, channel in
                total + abs(Double(actual[offset + channel]) - Double(reference[offset + channel]) * dim)
            } / 3 <= 6
        }.count
        Log.debug("native workspaces: wallpaper matches \(matching)/\(samples.count), intensity \(dim)")
        return Double(matching) / Double(samples.count) >= 0.98
    }
}
