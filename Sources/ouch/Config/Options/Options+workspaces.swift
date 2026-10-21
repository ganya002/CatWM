import AppKit

extension Options {
    static let workspaces: [ConfigOption] = [
        .bool("virtual-workspaces", \.virtualWorkspaces)
            .documented("bool", "true: Ouch controls native Desktops. false: macOS controls switching. "
                + "See [workspaces.md](workspaces.md)")
            .section("workspaces")
            .note("Ouch controls native Desktops, workspace keys, animation and Overview.")
            .setting(.windows, "windows.workspaces", "Control macOS Desktops with Ouch",
                     help: "Ouch controls workspace keys, animation and Overview",
                     keywords: "spaces desktops virtual", section: "Workspaces"),
        .bool("stay-on-workspace-after-close", \.stayOnWorkspaceAfterClose)
            .documented("bool", "")
            .setting(.windows, "windows.stay", "Stay on this workspace when closing a window", keywords: "close jump",
                     advanced: true, section: "Workspaces", enabled: { $0.virtualWorkspaces }),
        .bool("remove-empty-workspaces", \.removesEmptyWorkspaces)
            .documented("bool", "true: an empty workspace goes away when you leave it, and Ouch keeps its Desktop "
                + "as a spare so that the next new workspace opens instantly")
            .setting(.windows, "windows.removeEmpty", "Remove empty workspaces when you leave them",
                     help: "New workspaces then open instantly on the spare Desktop",
                     keywords: "clean auto delete desktop spare instant", section: "Workspaces",
                     enabled: { $0.virtualWorkspaces }),
        .choice("sort-strategy", \.sortStrategy, noun: "sort strategy")
            .documented(nil, "the grouping Overview opens with")
            .note("Overview: the grouping it opens with (task, app, focus or none), and how many windows one\n"
                + "workspace holds before Ouch offers Overview (0 turns the offer off).")
            .setting(.windows, "windows.sortStrategy", "Overview groups windows by",
                     help: "How the Overview panel groups them when it opens",
                     keywords: "group organize task app focus panel", section: "Workspaces",
                     enabled: { $0.virtualWorkspaces }),
        .number("sort-nudge", \.sortNudge, valid: 0...100, make: { Int($0) }, text: { "\($0)" }, number: { Double($0) })
            .documented("0–100 (whole number)",
                        "windows on one workspace before Ouch offers Overview; `0` turns the offer off")
            .setting(.windows, "windows.sortNudge", "Suggest Overview for a crowded workspace",
                     help: "A tip under the menu bar icon, at most once a day",
                     keywords: "tip packed many windows organize", range: 3...20, section: "Workspaces",
                     enabled: { $0.virtualWorkspaces })
    ]
}
