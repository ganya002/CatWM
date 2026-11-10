import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor struct OnboardingLayoutTests {
    @Test(arguments: [true, false])
    func tryItCompletesTheLayoutLesson(hasPrevious: Bool) throws {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        let coach = try #require(Coach(lesson: TourLesson(), statusButton: nil, windowManager: manager) { _ in })
        let config = Config.parse("""
        bind = ALT, n, cyclelayout, next
        \(hasPrevious ? "bind = ALT, p, cyclelayout, prev" : "")
        """)
        coach.book = BindBook(binds: config.bindings)
        let planned = try #require(Steps.layouts(coach))
        coach.step = planned.build(coach)
        manager.onDispatch = { dispatcher, argument, inMode in
            coach.handle(.command(dispatcher, argument, inMode: inMode))
        }
        defer { manager.onDispatch = nil }
        let simulate = try #require(coach.step?.simulate)
        simulate()
        #expect(!coach.done)
        simulate()
        #expect(coach.done)
        #expect(coach.seen == (hasPrevious ? ["next", "prev"] : ["next"]))
    }
}
