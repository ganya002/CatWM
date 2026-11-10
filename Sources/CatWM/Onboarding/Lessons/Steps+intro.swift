import AppKit
import CatWMKit

extension Steps {
    typealias SummaryRow = (caps: [String], label: String)

    static func intro(_ coach: Coach, title: String, button: String) -> PlannedStep {
        PlannedStep { coach in
            let text: String
            if let desk = coach.desk, let other = coach.other {
                let deskCount = KeyWords.count(PracticeDesk.deskCount)
                let otherCount = KeyWords.count(PracticeDesk.otherCount).lowercased()
                text = "\(deskCount) practice windows on workspace \(desk), \(otherCount) on \(other)."
                    + (coach.original.map { " Yours wait on \($0)." } ?? "")
            } else {
                let total = KeyWords.count(PracticeDesk.deskCount + PracticeDesk.otherCount)
                text = "\(total) practice windows. Your apps aren't touched."
            }
            return Step(title: title, text: text, button: button, count: 0)
        }
    }

    static func summary(_ coach: Coach, title: String, tutorial: Bool = false) -> PlannedStep {
        let book = coach.book
        let config = coach.windowManager.config
        var summary = Coach.Summary(tutorial: tutorial)
        if book.enter != nil {
            summary.modeCaps = book.enterCaps(long: false)
            summary.modeName = "\(book.mode.capitalized) mode"
            if config.keyboardHelp { summary.helpKey = config.keyboardHelpKey }
        }
        let modeTitle = book.mode.isEmpty ? "Keys" : "In \(book.mode) mode"
        summary.groups = [.init(title: modeTitle, column: 1, rows: inModeRows(coach)),
                          .init(title: "More", column: 2, rows: moreRows(book)),
                          .init(title: "From anywhere", column: 2, rows: anywhereRows(book))]
            .filter { !$0.rows.isEmpty }
        return PlannedStep { _ in
            Step(title: title,
                 text: "Your own windows are back where you left them.",
                 button: "Finish", count: 0, summary: summary)
        }
    }

    private static func cap(_ binding: KeyBinding?) -> [String] {
        binding.map { KeyWords.caps($0, long: false) } ?? []
    }

    private static func inModeRows(_ coach: Coach) -> [SummaryRow] {
        let book = coach.book
        let config = coach.windowManager.config
        var rows: [SummaryRow] = []
        let dirs = book.directions.compactMap { book.find([WindowActions.movefocus], $0) }
        if dirs.count == 4 { rows.append((dirs.map { KeyWords.keyLabel($0.keyCode, long: false) }, "Move focus")) }
        let moves = book.directions.compactMap { book.find([WindowActions.movewindow, WindowActions.swapwindow], $0) }
        if moves.count == 4 {
            let keys = moves.map { KeyWords.keyLabel($0.keyCode, long: false) }
            rows.append((KeyWords.modLabels(moves[0].mods, long: false) + keys, "Move the window"))
        }
        if let swap = book.find([WindowActions.layoutmsg], "swapwithmaster") {
            rows.append((cap(swap), "Swap with the main pane"))
        }
        if let (grow, shrink) = book.resize { rows.append((cap(shrink) + cap(grow), "Shrink / grow")) }
        if let next = book.find([WindowActions.cyclelayout], "next") { rows.append((cap(next), "Next layout")) }
        if let workspace = book.find([WindowActions.workspace], "1") {
            rows.append((KeyWords.modLabels(workspace.mods, long: false) + ["1–0"], "Switch workspace"))
        }
        if book.enter != nil, config.keyboardHelp { rows.append(([config.keyboardHelpKey], "Keyboard help")) }
        return rows
    }

    private static func moreRows(_ book: BindBook) -> [SummaryRow] {
        var rows: [SummaryRow] = []
        if let zoom = book.find([WindowActions.fullscreen]) { rows.append((cap(zoom), "Zoom")) }
        if let native = book.find([WindowActions.nativefullscreen]) { rows.append((cap(native), "macOS full screen")) }
        if let float = book.find([WindowActions.togglefloating]) { rows.append((cap(float), "Float or tile")) }
        return rows
    }

    private static func anywhereRows(_ book: BindBook) -> [SummaryRow] {
        var rows: [SummaryRow] = []
        if let sort = book.find([WindowActions.sort], global: true) { rows.append((cap(sort), "Overview")) }
        if let workspace = book.find([WindowActions.workspace], "1", global: true) {
            rows.append((KeyWords.modLabels(workspace.mods, long: false) + ["1–0"], "Switch workspace"))
        }
        return rows
    }
}
