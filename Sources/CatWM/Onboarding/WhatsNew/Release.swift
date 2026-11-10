import AppKit
import CatWMKit

struct Release {
    struct Feature {
        let id: String
        let symbol: String
        let title: String
        let text: String
        var action: (label: String, run: () -> Void)?
        var tour: ((Coach) -> [PlannedStep])?
    }

    let version: String
    let features: [Feature]
}

extension Release {
    static let all = [
        Release(version: "0.4", features: [
            Feature(id: "0.4.defaultbinds", symbol: "keyboard",
                    title: "More keys out of the box",
                    text: "Control Option H J K L moves focus from any app. Window mode has more keys too.",
                    tour: { Steps.focusGlobal($0).map { [$0] } ?? [] }),
            Feature(id: "0.4.splitbar", symbol: "rectangle.split.2x1",
                    title: "Drag the split bar",
                    text: "Drag the split bar to resize the main pane. Click it to swap the sides."),
            Feature(id: "0.4.sendkeys", symbol: "arrow.right.square",
                    title: "Move a window with Ctrl Shift",
                    text: "Press Ctrl Shift and a number or an arrow key to send the window to a workspace.",
                    tour: { Steps.sendGlobal($0).map { [$0] } ?? [] }),
            Feature(id: "0.4.configs", symbol: "slider.horizontal.3",
                    title: "Edit the built-in configs",
                    text: "Change a built-in config and CatWM keeps your edits. No copy is made.",
                    action: ("Open Shortcuts", { SettingsWindow.shared.show(pane: .shortcuts) }))
        ]),
        Release(version: "0.3", features: [
            Feature(id: "0.3.switcher", symbol: "rectangle.stack",
                    title: "Switch to any window",
                    text: "One list of every window on every workspace and Desktop. Type to search.",
                    action: ("Switcher settings", { SettingsWindow.shared.show(pane: .windows) }),
                    tour: { Steps.switcher($0).map { [$0] } ?? [] }),
            Feature(id: "0.3.quickactions", symbol: "cursorarrow.rays",
                    title: "Quick actions at the pointer",
                    text: "In window mode, tap the mode's modifier. Save a template, or dim the other windows.",
                    action: ("Pointer settings", { SettingsWindow.shared.show(pane: .windows) }),
                    tour: { Steps.quickActions($0) }),
            Feature(id: "0.3.desktops", symbol: "rectangle.on.rectangle",
                    title: "Workspaces are macOS Desktops",
                    text: "CatWM animates the switch with your Motion settings. Swipes follow your fingers."),
            Feature(id: "0.3.templates", symbol: "rectangle.3.group",
                    title: "Save a workspace as a template",
                    text: "Save the windows of a workspace, and open them again later.",
                    action: ("Open Templates", { SettingsWindow.shared.show(pane: .templates) })),
            Feature(id: "0.3.overview", symbol: "square.grid.3x2",
                    title: "Sort is now Overview",
                    text: "It also shows windows in macOS full screen as their own workspaces.",
                    tour: { Steps.sortTry($0) })
        ])
    ]
}
