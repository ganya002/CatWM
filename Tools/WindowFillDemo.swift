import AppKit

@MainActor final class WindowFillDemo: NSObject {
    private let child = Process()
    private let request = "/tmp/catwm-fill-demo-\(UUID().uuidString).json"
    private let width = NSSlider(value: 800, minValue: 500, maxValue: 900, target: nil, action: nil)
    private let height = NSSlider(value: 420, minValue: 320, maxValue: 650, target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private var controls: CatWMPanel?
    private var fill: WindowResizeFill?
    private var timer: Timer?
    private var window: CGWindowID = 0
    private var origin = CGPoint.zero
    private var catchingUp = false

    static func run(_ app: NSApplication) {
        let demo = WindowFillDemo()
        Task {
            do { try await demo.open() } catch {
                fputs("fill demo: \(error)\n", stderr)
                demo.close()
            }
        }
        withExtendedLifetime(demo) { app.run() }
    }

    private func open() async throws {
        let pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--child", "--demo-child", "--style=browser"]
        child.standardOutput = pipe
        child.environment = ProcessInfo.processInfo.environment.merging(
            ["CATWM_FILL_DEMO_REQUEST": request]) { _, new in new }
        try child.run()
        let line = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let id = CGWindowID(line), let screen = NSScreen.screens.first else { throw FillProbeError.missingWindow }
        window = id
        var source: (image: CGImage, frame: CGRect)?
        for _ in 0..<30 {
            source = WindowSceneCapture.windowImage(id)
            if source != nil { break }
            await withCheckedContinuation { next in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { next.resume() }
            }
        }
        guard let source, let appearance = WindowFillAppearance(image: source.image, size: source.frame.size) else {
            throw FillProbeError.captureUnavailable
        }
        origin = source.frame.origin
        width.maxValue = min(900, Double(screen.frame.width - 440))
        width.doubleValue = min(800, width.maxValue)
        height.maxValue = min(650, Double(screen.frame.height - origin.y - 60))
        height.doubleValue = min(420, height.maxValue)
        fill = WindowResizeFill(window: id, appearance: appearance)
        makeControls(on: screen)
        timer = Timer(timeInterval: 0.1, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        showFill()
        print("demo_ready parent \(getpid()) child \(child.processIdentifier) window \(id)")
    }

    private func makeControls(on screen: NSScreen) {
        let panel = CatWMPanel(role: .card(.floating), frame: CGRect(
            x: screen.frame.maxX - 330, y: screen.frame.maxY - 440, width: 290, height: 300))
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.onClose = { [weak self] in self?.close() }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        let title = NSTextField(labelWithString: "CatWM color-fill demo")
        let hint = NSTextField(wrappingLabelWithString:
            "Drag the sliders to expose the fill. Catch up resizes the real browser window. Close ends this demo.")
        for slider in [width, height] {
            slider.target = self; slider.action = #selector(showFill); slider.isContinuous = true
        }
        let views: [NSView] = [title, hint, NSTextField(labelWithString: "Width"), width,
                               NSTextField(labelWithString: "Height"), height, status]
        for view in views { stack.addArrangedSubview(view) }
        let buttons = NSStackView(views: [
            NSButton(title: "Show fill", target: self, action: #selector(showFill)),
            NSButton(title: "Catch up", target: self, action: #selector(catchUp)),
            NSButton(title: "Close", target: self, action: #selector(close))
        ])
        stack.addArrangedSubview(buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let view = panel.contentView {
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                                         stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                                         stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16)])
        }
        controls = panel
        panel.orderFrontRegardless()
    }

    private var desired: CGRect {
        CGRect(origin: origin, size: CGSize(width: width.doubleValue, height: height.doubleValue))
    }

    @objc private func showFill() {
        catchingUp = false
        guard let actual = WindowSceneCapture.currentFrame(window) else { return }
        fill?.update(desired: desired, actual: actual)
        status.stringValue = "\(Int(desired.width)) × \(Int(desired.height)) — color-only growth"
    }

    @objc private func catchUp() {
        do {
            try JSONEncoder().encode(desired.size).write(to: URL(fileURLWithPath: request), options: .atomic)
            catchingUp = true
            kill(child.processIdentifier, SIGUSR2)
        } catch { status.stringValue = "Resize request failed: \(error.localizedDescription)" }
    }

    @objc private func poll() {
        guard child.isRunning, WindowServerList.onScreen()?.contains(window) == true else { close(); return }
        guard catchingUp, let actual = WindowSceneCapture.currentFrame(window) else { return }
        fill?.update(desired: desired, actual: actual)
        if actual.approxEqual(desired, tolerance: 0.25) {
            catchingUp = false
            status.stringValue = "Real window caught up; fill removed."
        }
    }

    @objc private func close() {
        timer?.invalidate()
        fill?.close()
        controls?.orderOut(nil)
        if child.isRunning { child.terminate() }
        if FileManager.default.fileExists(atPath: request) {
            do { try FileManager.default.removeItem(atPath: request) } catch {
                fputs("fill demo cleanup: \(error)\n", stderr)
            }
        }
        NSApp.terminate(nil)
    }
}
