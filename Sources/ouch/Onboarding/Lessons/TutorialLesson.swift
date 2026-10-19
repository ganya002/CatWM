import AppKit

final class TutorialLesson: Lesson {
    struct Chapter {
        let id: String
        let name: String
        let steps: [PlannedStep]
    }

    static let savedKey = "tutorial.chapter"
    private static let doneKey = "tutorial.done"

    private var chapters: [Chapter] = []
    private var plan: [(chapter: Int, step: PlannedStep)] = []
    private(set) var startIndex = 0
    let pausable = true
    var count: Int { plan.count }

    static var paused: (id: String, name: String)? {
        guard let s = UserDefaults.standard.string(forKey: savedKey) else { return nil }
        let parts = s.split(separator: "|", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
    static var finishedOnce: Bool { UserDefaults.standard.bool(forKey: doneKey) }
    static func forget() { UserDefaults.standard.removeObject(forKey: savedKey) }

    func prepare(_ c: Coach) {
        func chapter(_ id: String, _ name: String, _ steps: [PlannedStep?]) {
            let list = steps.compactMap { $0 }
            if !list.isEmpty { chapters.append(Chapter(id: id, name: name, steps: list)) }
        }
        chapter("welcome", "Welcome", [Steps.intro(c, title: "Learn every key", button: "Start")])
        chapter("mode", "Window mode", [Steps.modeOn(c), Steps.modeOff(c), Steps.modeDrill(c), Steps.help(c)])
        chapter("focus", "Focus", [Steps.focus(c), Steps.cycle(c), Steps.focusDrill(c), Steps.focusDrill(c), Steps.focusDrill(c)])
        chapter("move", "Moving windows", [Steps.move(c), Steps.main(c), Steps.mainDrill(c), Steps.mainDrill(c)])
        chapter("main", "The main pane", [Steps.masters(c), Steps.resize(c)])
        chapter("layouts", "Layouts", [Steps.layouts(c), Steps.layoutDrill(c), Steps.layoutDrill(c)])
        chapter("zoom", "Zoom and float", [Steps.zoom(c), Steps.float(c), Steps.retile(c)])
        chapter("workspaces", "Workspaces", [Steps.visit(c), Steps.back(c), Steps.neighbours(c), Steps.workspaceDrill(c), Steps.send(c)])
        chapter("global", "Global keys", [Steps.modeOff(c), Steps.global(c)])
        chapter("displays", "Displays", [Steps.monitor(c)])
        chapter("sort", "Overview", Steps.sortTry(c))
        chapter("done", "Done", [Steps.summary(c, title: "That's every key")])
        for (i, ch) in chapters.enumerated() { plan += ch.steps.map { (i, $0) } }
        if let saved = Self.paused, let i = chapters.firstIndex(where: { $0.id == saved.id }),
           let start = plan.firstIndex(where: { $0.chapter == i }) {
            startIndex = start
        }
    }

    func step(_ i: Int, in coach: Coach) -> Coach.Step { plan[i].step.build(coach) }

    func ended(_ how: Coach.Ending, at index: Int) {
        let d = UserDefaults.standard
        switch how {
        case .finished, .tutorial:
            Self.forget()
            d.set(true, forKey: Self.doneKey)
        case .paused, .skipped:
            let ch = chapters[plan[min(index, plan.count - 1)].chapter]
            if ch.id == "welcome" || ch.id == "done" { Self.forget() } else { d.set("\(ch.id)|\(ch.name)", forKey: Self.savedKey) }
        }
    }
}
