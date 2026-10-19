import AppKit

final class TourLesson: Lesson {
    private var plan: [PlannedStep] = []
    let pausable = false
    let startIndex = 0
    var count: Int { plan.count }

    func prepare(_ coach: Coach) {
        plan = [Steps.modeOn(coach), Steps.help(coach), Steps.focus(coach), Steps.move(coach), Steps.main(coach),
                Steps.resize(coach), Steps.zoom(coach), Steps.float(coach), Steps.layouts(coach), Steps.visit(coach),
                Steps.send(coach), Steps.modeOff(coach), Steps.global(coach), Steps.sortIntro(coach)]
            .compactMap(\.self)
        plan.append(Steps.summary(coach, title: "You learned the *basics*", tutorial: true))
    }

    func step(_ i: Int, in coach: Coach) -> Coach.Step { plan[i].build(coach) }

    func ended(_: Coach.Ending, at _: Int) {}
}
