import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct SingleWindowPaddingTests {
    @Test func aWindowAloneGetsTheExtraPaddingAndPairsDoNot() async throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let fake = FakeBackend()
        fake.addScreen(frame: screen, visible: screen)
        let first = fake.addWindow(pid: -501, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        let manager = fake.makeManager {
            $0.paddingLeft = 10; $0.paddingRight = 10; $0.paddingTop = 10; $0.paddingBottom = 10
            $0.singleWindowPadding = 20
        }
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: first) == CGRect(x: 30, y: 30, width: 1380, height: 840))

        let second = fake.addWindow(pid: -502)
        #expect(await fake.settle(manager))
        #expect(fake.frame(of: first).minX == 10)
        #expect(fake.frame(of: second).maxX == 1430)
    }
}
