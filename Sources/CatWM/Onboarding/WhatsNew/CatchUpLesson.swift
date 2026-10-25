import AppKit

final class CatchUpLesson: Lesson {
    private let features: [Release.Feature]
    private var plan: [PlannedStep] = []
    let pausable = false
    let startIndex = 0
    var count: Int { plan.count }

    init(features: [Release.Feature]) {
        self.features = features
    }

    func prepare(_ coach: Coach) {
        plan = features.flatMap { $0.tour?(coach) ?? [] }
        plan.append(PlannedStep { _ in
            Coach.Step(title: "You're caught up", text: "What's New, in the Help menu, shows this again.",
                       button: "Finish", count: 0)
        })
    }

    func step(_ i: Int, in coach: Coach) -> Coach.Step { plan[i].build(coach) }

    func ended(_: Coach.Ending, at _: Int) {}
}
