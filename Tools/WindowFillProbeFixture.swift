import AppKit
import QuartzCore
import WebKit

enum FillProbeFixture {
    enum Style: String { case native, browser, borderless, sidebar, translucent }

    static var style: Style {
        let argument = CommandLine.arguments.first { $0.hasPrefix("--style=") }
        let name = argument.map { String($0.dropFirst(8)) } ?? "native"
        guard let style = Style(rawValue: name) else {
            fputs("fill probe: unknown style \(name)\n", stderr)
            exit(2)
        }
        return style
    }

    final class Pattern: NSView {
        var updated = false
        override func draw(_: NSRect) {
            (style == .translucent ? NSColor.white.withAlphaComponent(0.7) : .white).setFill()
            bounds.fill()
            if style == .sidebar {
                NSColor(calibratedRed: 0.2, green: 0.35, blue: 0.55, alpha: 1).setFill()
                CGRect(x: 0, y: 0, width: 160, height: bounds.height).fill()
            }
            (updated ? NSColor.systemBlue : .systemRed).setFill()
            CGRect(x: 40, y: 40, width: 100, height: 100).fill()
            "Live text and traffic lights stay unchanged".draw(at: CGPoint(x: 35, y: 170), withAttributes: [
                .font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black
            ])
        }
    }

    final class Page: NSObject, WKNavigationDelegate {
        let ready: () -> Void
        init(ready: @escaping () -> Void) { self.ready = ready }
        func webView(_: WKWebView, didFinish _: WKNavigation) { ready() }
    }

    static func run(_ app: NSApplication) -> Never {
        let window = makeWindow()
        let original = window.frame
        let pattern = Pattern(frame: window.contentView?.bounds ?? .zero)
        let browser = style == .browser ? WKWebView(frame: pattern.frame) : nil
        window.contentView = browser ?? pattern
        let page = Page { print(window.windowNumber); fflush(stdout) }
        browser?.navigationDelegate = page
        browser?.loadHTMLString(html, baseURL: nil)
        signal(SIGUSR1, SIG_IGN)
        let updates = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        updates.setEventHandler {
            let old = original
            window.setFrame(CGRect(x: old.minX, y: old.minY - 100,
                                   width: old.width + 300, height: old.height + 100), display: true)
            pattern.updated = true; pattern.needsDisplay = true
            let script = "document.getElementById('marker').style.background='#007aff'; innerHeight"
            browser?.evaluateJavaScript(script) { value, error in
                if let error {
                    fputs("browser fixture update failed: \(error)\n", stderr)
                } else { fputs("browser fixture viewport height \(String(describing: value))\n", stderr) }
            }
            window.displayIfNeeded(); CATransaction.flush()
        }
        updates.resume()
        signal(SIGUSR2, SIG_IGN)
        let partial = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        partial.setEventHandler { resizePartially(window, original: original) }
        partial.resume()
        if CommandLine.arguments.contains("--background") {
            window.orderBack(nil)
        } else { window.orderFrontRegardless() }
        window.displayIfNeeded()
        if browser == nil { print(window.windowNumber); fflush(stdout) }
        withExtendedLifetime((window, updates, partial, page)) { app.run() }
        exit(0)
    }

    private static func resizePartially(_ window: NSWindow, original: CGRect) {
        if let path = ProcessInfo.processInfo.environment["CATWM_FILL_DEMO_REQUEST"] {
            do {
                let size = try JSONDecoder().decode(CGSize.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                window.setFrame(CGRect(x: original.minX, y: original.maxY - size.height,
                                       width: size.width, height: size.height), display: true)
            } catch { fputs("fill demo resize: \(error)\n", stderr) }
        } else {
            window.setFrame(CGRect(x: original.minX, y: original.minY - 50,
                                   width: original.width + 100, height: original.height + 50), display: true)
        }
        window.displayIfNeeded(); CATransaction.flush()
    }

    static func checkAlpha(_ id: CGWindowID, size: CGSize) throws {
        guard let snapshot = WindowSceneCapture.windowImage(id) else { throw FillProbeError.captureUnavailable }
        let bitmap = NSBitmapImageRep(cgImage: snapshot.image)
        guard let sample = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2),
              sample.alphaComponent > 0.6, sample.alphaComponent < 0.9,
              WindowFillAppearance(image: snapshot.image, size: size) == nil else {
            throw FillProbeError.pixels("translucency was replaced by opaque paint")
        }
        print("translucent_window_keeps_native_rendering true")
    }

    static func makeBackdrop(_ area: CGRect, window id: CGWindowID, screen: NSScreen) -> CatWMPanel {
        let background = area.insetBy(dx: -32, dy: -32)
        let backdrop = CatWMPanel(role: .overlay(.normal, clickThrough: true), frame: CGRect(
            x: background.minX, y: screen.frame.height - background.maxY,
            width: background.width, height: background.height))
        backdrop.backgroundColor = .systemGreen; backdrop.isOpaque = true
        backdrop.order(.below, relativeTo: Int(id)); backdrop.displayIfNeeded()
        return backdrop
    }

    private static func makeWindow() -> NSWindow {
        var mask: NSWindow.StyleMask = style == .borderless ? [.borderless] : [.titled, .closable]
        if style == .browser { mask.formUnion([.fullSizeContentView, .miniaturizable, .resizable]) }
        let window = NSWindow(contentRect: CGRect(x: 160, y: 250, width: 500, height: 320),
                              styleMask: mask, backing: .buffered, defer: false)
        if CommandLine.arguments.contains("--demo-child"), let screen = NSScreen.screens.first {
            window.setFrameOrigin(CGPoint(x: screen.frame.minX + 80, y: screen.frame.maxY - 160 - window.frame.height))
        }
        window.title = "CatWM disposable \(style.rawValue) fill probe"
        window.animationBehavior = .none
        if CommandLine.arguments.contains("--light") { window.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--dark") { window.appearance = NSAppearance(named: .darkAqua) }
        if style == .browser { window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true }
        window.isOpaque = style != .translucent
        window.backgroundColor = style == .translucent ? .clear : .white
        return window
    }

    private static let html = """
    <!doctype html><meta charset="utf-8"><style>
    html,body {margin:0; height:100%; background:white; color:black; font:18px -apple-system}
    #tabs {height:32px; padding-left:100px; background:#dce2ec; font-size:13px; line-height:32px}
    #toolbar {height:35px; background:#f1f3f4; border-bottom:1px solid #d0d0d0; padding-left:90px}
    #address {display:inline-block; margin:5px; padding:3px 20px; background:white; border-radius:12px; font-size:13px}
    #text {position:absolute; left:35px; top:145px}
    #marker {position:absolute; left:40px; bottom:40px; width:100px; height:100px; background:#ff3b30}
    </style><div id="tabs">A browser tab</div><div id="toolbar"><span id="address">catwm.test</span></div>
    <div id="text">Live web content stays unchanged</div><div id="marker"></div>
    """
}
