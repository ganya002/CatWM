import AppKit
import CatWMKit
import SwiftUI

protocol Lesson: AnyObject {
    func prepare(_ coach: Coach)
    var count: Int { get }
    var startIndex: Int { get }
    var pausable: Bool { get }
    func step(_ i: Int, in coach: Coach) -> Coach.Step
    func ended(_ how: Coach.Ending, at index: Int)
}

struct PlannedStep {
    let build: (Coach) -> Coach.Step
}

enum Steps {
    typealias Step = Coach.Step
}

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
