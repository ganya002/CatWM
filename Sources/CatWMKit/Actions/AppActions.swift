import AppKit

extension WindowActions {
    package static let submap = WindowAction.text(
        "submap", "app", "Enter a key mode, or leave it", .text("name", "The mode name, or `reset` to leave the mode"),
        pickers: [
            ActionPicker("Enter Window Mode", .app, "window", "keyboard", order: -1),
            ActionPicker("Leave Mode", .app, "reset", "escape", order: -1)
        ]
    ) { Hotkeys.shared.setSubmap($0.arg) }

    package static let reload = WindowAction(
        name: "reload", group: "app", summary: "Read the config file again",
        pickers: [ActionPicker("Reload Config", .app, "", "arrow.triangle.2.circlepath")]
    ) { $0.manager.reload() }

    package static let exit = WindowAction(
        name: "exit", group: "app", summary: "Quit CatWM",
        pickers: [ActionPicker("Quit CatWM", .app, "", "xmark.circle")]
    ) { _ in
        RunLoop.main.perform(inModes: [.common, .modalPanel]) { NSApp.terminate(nil) }
    }

    package static let exec = WindowAction(
        name: "exec", group: "app", summary: "Run a shell command", access: .keybindOnly,
        pickers: [ActionPicker("Run Command", .commands, "", "terminal")]
    ) { $0.manager.exec($0.arg) }

    package static let launch = WindowAction(
        name: "launch", group: "app", summary: "Open an app, file, URL or command", access: .keybindOnly
    ) { $0.manager.launchCommand($0.arg) }
}
