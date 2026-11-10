import AppKit
import CatWMKit

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
        guard let saved = Instance.defaults.string(forKey: savedKey) else { return nil }
        let parts = saved.split(separator: "|", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
    static var finishedOnce: Bool { Instance.defaults.bool(forKey: doneKey) }
    static func forget() { Instance.defaults.removeObject(forKey: savedKey) }

    func prepare(_ coach: Coach) {
        func chapter(_ id: String, _ name: String, _ steps: [PlannedStep?]) {
            let list = steps.compactMap(\.self)
            if !list.isEmpty { chapters.append(Chapter(id: id, name: name, steps: list)) }
        }
        chapter("welcome", "Welcome", [Steps.intro(coach, title: "Learn every key", button: "Start")])
        chapter("mode", "Window mode",
                [Steps.modeOn(coach), Steps.modeOff(coach), Steps.modeDrill(coach), Steps.help(coach)])
        chapter("focus", "Focus",
                [Steps.focus(coach), Steps.cycle(coach),
                 Steps.focusDrill(coach), Steps.focusDrill(coach), Steps.focusDrill(coach)])
        chapter("move", "Moving windows",
                [Steps.move(coach), Steps.main(coach), Steps.mainDrill(coach), Steps.mainDrill(coach)])
        chapter("main", "The main pane", [Steps.mainCount(coach), Steps.resize(coach)])
        chapter("layouts", "Layouts", [Steps.layouts(coach), Steps.layoutDrill(coach), Steps.layoutDrill(coach)])
        chapter("zoom", "Zoom and float", [Steps.zoom(coach), Steps.float(coach), Steps.retile(coach)])
        chapter("workspaces", "Workspaces",
                [Steps.visit(coach), Steps.back(coach), Steps.neighbours(coach),
                 Steps.workspaceDrill(coach), Steps.send(coach)])
        chapter("global", "Global keys", [Steps.modeOff(coach), Steps.global(coach)])
        chapter("displays", "Displays", [Steps.monitor(coach)])
        chapter("sort", "Overview", Steps.sortTry(coach))
        chapter("done", "Done", [Steps.summary(coach, title: "That's every key")])
        for (i, entry) in chapters.enumerated() { plan += entry.steps.map { (i, $0) } }
        if let saved = Self.paused, let i = chapters.firstIndex(where: { $0.id == saved.id }),
           let start = plan.firstIndex(where: { $0.chapter == i }) {
            startIndex = start
        }
    }

    func step(_ i: Int, in coach: Coach) -> Coach.Step { plan[i].step.build(coach) }

    func ended(_ how: Coach.Ending, at index: Int) {
        let defaults = Instance.defaults
        switch how {
        case .finished, .tutorial:
            Self.forget()
            defaults.set(true, forKey: Self.doneKey)
        case .paused, .skipped:
            let chapter = chapters[plan[min(index, plan.count - 1)].chapter]
            if chapter.id == "welcome" || chapter.id == "done" {
                Self.forget()
            } else {
                defaults.set("\(chapter.id)|\(chapter.name)", forKey: Self.savedKey)
            }
        }
    }
}
