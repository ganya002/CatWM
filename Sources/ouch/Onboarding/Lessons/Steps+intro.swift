import AppKit

extension Steps {
    static func intro(_ c: Coach, title: String, button: String) -> PlannedStep {
        PlannedStep { c in
            let text: String
            if let desk = c.desk, let other = c.other {
                text = "\(KeyWords.count(PracticeDesk.deskCount)) practice windows on workspace \(desk), \(KeyWords.count(PracticeDesk.otherCount).lowercased()) on \(other)."
                    + (c.original.map { " Yours wait on \($0)." } ?? "")
            } else {
                text = "\(KeyWords.count(PracticeDesk.deskCount + PracticeDesk.otherCount)) practice windows. Your apps aren't touched."
            }
            return Step(title: title, text: text, button: button, count: 0)
        }
    }

    static func summary(_ c: Coach, title: String, tutorial: Bool = false) -> PlannedStep {
        let b = c.book
        func cap(_ k: KeyBinding?) -> [String] { k.map { KeyWords.caps($0, long: false) } ?? [] }
        var inMode: [(caps: [String], label: String)] = []
        let dirs = b.directions.compactMap { b.find(["movefocus"], $0) }
        if dirs.count == 4 { inMode.append((dirs.map { KeyWords.keyLabel($0.keyCode, long: false) }, "Move focus")) }
        let moves = b.directions.compactMap { b.find(["movewindow", "swapwindow"], $0) }
        if moves.count == 4 {
            inMode.append((KeyWords.modLabels(moves[0].mods, long: false) + moves.map { KeyWords.keyLabel($0.keyCode, long: false) },
                           "Move the window"))
        }
        if let s = b.find(["layoutmsg"], "swapwithmaster") { inMode.append((cap(s), "Swap with the main pane")) }
        if let (g, s) = b.resize { inMode.append((cap(s) + cap(g), "Shrink / grow")) }
        if let n = b.find(["cyclelayout"], "next") { inMode.append((cap(n), "Next layout")) }
        if let w = b.find(["workspace"], "1") { inMode.append((KeyWords.modLabels(w.mods, long: false) + ["1–0"], "Switch workspace")) }
        if b.enter != nil, c.wm.config.keyboardHelp { inMode.append(([c.wm.config.keyboardHelpKey], "Keyboard help")) }
        var more: [(caps: [String], label: String)] = []
        if let f = b.find(["fullscreen"]) { more.append((cap(f), "Zoom")) }
        if let f = b.find(["nativefullscreen"]) { more.append((cap(f), "macOS full screen")) }
        if let f = b.find(["togglefloating"]) { more.append((cap(f), "Float or tile")) }
        var anywhere: [(caps: [String], label: String)] = []
        if let s = b.find(["sort"], global: true) { anywhere.append((cap(s), "Overview")) }
        if let g = b.find(["workspace"], "1", global: true) { anywhere.append((KeyWords.modLabels(g.mods, long: false) + ["1–0"], "Switch workspace")) }

        var summary = Coach.Summary(tutorial: tutorial)
        if b.enter != nil {
            summary.modeCaps = b.enterCaps(long: false)
            summary.modeName = "\(b.mode.capitalized) mode"
            if c.wm.config.keyboardHelp { summary.helpKey = c.wm.config.keyboardHelpKey }
        }
        let modeTitle = b.mode.isEmpty ? "Keys" : "In \(b.mode) mode"
        summary.groups = [.init(title: modeTitle, column: 1, rows: inMode),
                          .init(title: "More", column: 2, rows: more),
                          .init(title: "From anywhere", column: 2, rows: anywhere)].filter { !$0.rows.isEmpty }
        return PlannedStep { _ in
            Step(title: title,
                 text: "Your own windows are back where you left them.",
                 button: "Finish", count: 0, summary: summary)
        }
    }
}
