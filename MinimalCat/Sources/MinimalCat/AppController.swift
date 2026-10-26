import AppKit
import Carbon.HIToolbox
import MinimalCatCore
import MinimalCatSystem
import ServiceManagement

/// Which physical key is the cat key. Caps Lock needs a key mapping. F18 is for keyboards that have it and for
/// VoiceOver, which owns Caps Lock.
enum CatKeyChoice: String {
    case capsLock, f18

    var symbol: String { self == .capsLock ? "⇪" : "F18" }
    var spoken: String { self == .capsLock ? "Caps Lock" : "F18" }
}

/// Owns every part of the running app and turns their events into engine calls.
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let system = AXSystem()
    private lazy var engine = Engine(system: system, memory: store.load())
    private var store = MemoryStore()
    private let keys = KeyTap()
    private let overlay = Overlay()
    private let find = FindPanel()
    private let hud = HUD()
    private lazy var focusWatcher = FocusWatcher { [weak self] in self?.engine.focused($0) }
    private lazy var displayWatcher = DisplayWatcher(save: { [weak self] in self?.saveLayout() },
                                                     restore: { [weak self] in self?.restoreLayout() })
    private var commands: [UInt16: Command] = [:]
    private var statusItem: NSStatusItem?
    private var welcome: Welcome?
    private var voiceOver: NSKeyValueObservation?
    private var trustPoll: Timer?

    private var paused: Bool {
        get { UserDefaults.standard.bool(forKey: "paused") }
        set { UserDefaults.standard.set(newValue, forKey: "paused") }
    }

    private var choice: CatKeyChoice {
        get {
            if NSWorkspace.shared.isVoiceOverEnabled { return .f18 }
            return CatKeyChoice(rawValue: UserDefaults.standard.string(forKey: "catKey") ?? "") ?? .capsLock
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "catKey") }
    }

    func applicationDidFinishLaunching(_: Notification) {
        commands = KeyLayout.commands()
        keys.onOutput = { [weak self] in self?.handle($0) }
        makeStatusItem()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        voiceOver = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { [weak self] _, _ in
            Task { @MainActor in self?.applyState() }
        }
        if AXIsProcessTrusted(), UserDefaults.standard.bool(forKey: "welcomed") {
            applyState()
        } else {
            showWelcome()
        }
    }

    func applicationWillTerminate(_: Notification) {
        saveLayout()
        CapsMapping.remove()
    }

    // MARK: - State

    /// Starts or stops every part so the app matches `paused`, the key choice and the permission.
    /// Off means off: when paused, no tap, no mapping, no watchers.
    private func applyState() {
        let run = !paused && AXIsProcessTrusted()
        if run {
            if choice == .capsLock {
                switch CapsMapping.apply() {
                case .applied: break
                case .othersMapping:
                    notify("Another app remaps Caps Lock. Minimal Cat uses F18 for now.", visible: true)
                case .failed:
                    notify("Could not use Caps Lock. Minimal Cat uses F18 for now.", visible: true)
                }
            } else {
                CapsMapping.remove()
            }
            engine.keyName = choice.symbol
            keys.start()
            focusWatcher.start()
            displayWatcher.start()
        } else {
            keys.stop()
            focusWatcher.stop()
            displayWatcher.stop()
            overlay.hide()
            CapsMapping.remove()
        }
        updateStatusIcon()
    }

    @objc private func inputSourceChanged() { commands = KeyLayout.commands() }

    // MARK: - Keys

    private func handle(_ output: CatKey.Output) {
        switch output {
        case .previousWindow: show(engine.previousWindow())
        case .showOverlay: showOverlay()
        case .hideOverlay: overlay.hide()
        case .act(let code):
            guard let command = commands[code] else { return }
            run(command, cause: .key)
            if overlay.isShown, command != .find, command != .cancel { showOverlay() }
        }
    }

    private func run(_ command: Command, cause: Cause) {
        show(engine.perform(command, cause: cause))
    }

    private func show(_ effect: Effect) {
        switch effect {
        case .none: break
        case let .notice(text, visible): notify(text, visible: visible)
        case .openFind:
            overlay.hide()
            let windows = engine.windows()
            find.show(windows, icons: icons(for: windows)) { [weak self] id in
                self?.system.focus(id)
            }
        case .cancel: overlay.hide()
        }
    }

    private func notify(_ text: String, visible: Bool) {
        if visible { hud.show(text) }
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func showOverlay() {
        let windows = engine.windows()
        let focused = system.focusedWindow()
        let icons = icons(for: windows)
        let rows = windows
            .map { window in
                OverlayView.Row(id: window.id, number: engine.slots.numbers[window.id], title: window.name,
                                app: window.app, icon: icons[window.id], focused: window.id == focused)
            }
            .sorted { ($0.number ?? 99) < ($1.number ?? 99) }
        overlay.show(rows, keyName: choice.symbol)
    }

    private func icons(for windows: [WindowInfo]) -> [WindowID: NSImage] {
        var byPID: [pid_t: NSImage] = [:]
        return windows.reduce(into: [:]) { icons, window in
            byPID[window.pid] = byPID[window.pid] ?? NSRunningApplication(processIdentifier: window.pid)?.icon
            icons[window.id] = byPID[window.pid]
        }
    }

    // MARK: - Layout memory

    private func saveLayout() {
        guard !paused else { return }
        engine.saveLayout()
        store.write(engine.memory)
    }

    private func restoreLayout() {
        guard !paused else { return }
        show(engine.restoreLayout())
        store.write(engine.memory)
    }

    // MARK: - Welcome

    private func showWelcome() {
        let welcome = Welcome(keyName: choice.spoken, symbol: choice.symbol) { [weak self] in
            UserDefaults.standard.set(true, forKey: "welcomed")
            self?.welcome = nil
            self?.applyState()
        }
        self.welcome = welcome
        welcome.show(trusted: AXIsProcessTrusted())
        trustPoll?.invalidate()
        trustPoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.welcome?.trusted()
                self?.applyState()
            }
        }
    }
}

// MARK: - Status menu

extension AppController {
    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let label = paused ? "Minimal Cat, off" : "Minimal Cat"
        let image = NSImage(systemSymbolName: paused ? "cat" : "cat.fill", accessibilityDescription: label)
            ?? NSImage(systemSymbolName: "square.split.2x1", accessibilityDescription: "Minimal Cat")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ready = !paused && AXIsProcessTrusted()
        for command in [Command.place(.left), .place(.right), .place(.top), .place(.bottom), .place(.big)] {
            menu.addItem(item(command, enabled: ready))
        }
        menu.addItem(.separator())
        menu.addItem(item(.focus(.left), enabled: ready))
        menu.addItem(item(.focus(.right), enabled: ready))
        menu.addItem(item(.find, enabled: ready))
        menu.addItem(.separator())
        let undo = item(.undo, enabled: ready)
        if let step = engine.history.undoSteps.last { undo.title = "Undo \(step.label)" }
        menu.addItem(undo)
        menu.addItem(item(.redo, enabled: ready))
        menu.addItem(.separator())

        let mode = NSMenuItem(title: paused ? "Turn On" : "Turn Off", action: #selector(togglePause), keyEquivalent: "")
        mode.target = self
        menu.addItem(mode)
        let keyMenu = NSMenu()
        for option in [CatKeyChoice.capsLock, .f18] {
            let entry = NSMenuItem(title: "\(option.spoken) (\(option.symbol))", action: #selector(chooseKey(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.representedObject = option.rawValue
            entry.state = choice == option ? .on : .off
            entry.isEnabled = !NSWorkspace.shared.isVoiceOverEnabled
            keyMenu.addItem(entry)
        }
        let keyItem = NSMenuItem(title: "Cat Key", action: nil, keyEquivalent: "")
        keyItem.submenu = keyMenu
        menu.addItem(keyItem)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if !AXIsProcessTrusted() {
            let grant = NSMenuItem(title: "Give Permission…", action: #selector(openWelcome), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }
        let help = NSMenuItem(title: "Show the Keys", action: #selector(openWelcome), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Minimal Cat", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func item(_ command: Command, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: command.title, action: enabled ? #selector(menuCommand(_:)) : nil,
                              keyEquivalent: "")
        item.target = self
        item.representedObject = command
        if let binding = command.binding { item.toolTip = "\(choice.symbol) \(KeyLayout.label(binding))" }
        return item
    }

    /// A menu command acts on the window that was in front before the menu opened.
    @objc private func menuCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? Command else { return }
        run(command, cause: .menu)
    }

    @objc private func togglePause() {
        paused.toggle()
        applyState()
        notify(paused ? "Minimal Cat is off" : "Minimal Cat is on", visible: true)
    }

    @objc private func chooseKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = CatKeyChoice(rawValue: raw) else { return }
        choice = option
        applyState()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            notify("Could not change Open at Login", visible: true)
        }
    }

    @objc private func openWelcome() { showWelcome() }
}
