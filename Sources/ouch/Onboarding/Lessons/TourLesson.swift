import AppKit

final class TourLesson: Lesson {
    private var plan: [PlannedStep] = []
    let pausable = false
    let startIndex = 0
    var count: Int { plan.count }

    func prepare(_ c: Coach) {
        plan = [Steps.modeOn(c), Steps.help(c), Steps.focus(c), Steps.move(c), Steps.main(c), Steps.resize(c),
                Steps.zoom(c), Steps.float(c), Steps.layouts(c), Steps.visit(c), Steps.send(c),
                Steps.modeOff(c), Steps.global(c), Steps.sortIntro(c)].compactMap { $0 }
        plan.append(Steps.summary(c, title: "You learned the *basics*", tutorial: true))
    }

    func step(_ i: Int, in coach: Coach) -> Coach.Step { plan[i].build(coach) }

    func ended(_ how: Coach.Ending, at index: Int) {}
}
