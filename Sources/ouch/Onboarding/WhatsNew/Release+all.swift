import AppKit

extension Release {
    static let all = [
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
                    text: "Ouch animates the switch with your Motion settings. Trackpad swipes follow your fingers."),
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
