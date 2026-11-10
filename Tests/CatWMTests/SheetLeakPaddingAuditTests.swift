import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct SheetLeakPaddingAuditTests {
    @Test func aStalledSheetReadKeepsTheAppAlive() {
        #expect(WindowManager.mayShowSheet(.stalled))
        #expect(WindowManager.mayShowSheet(.value([.value("AXButton"), .stalled])))
        #expect(WindowManager.mayShowSheet(.value([.value(kAXSheetRole)])))
        #expect(!WindowManager.mayShowSheet(.missing))
        #expect(!WindowManager.mayShowSheet(.value([.value("AXButton"), .missing])))
    }

    @Test func aForgottenWindowLeavesNoAnimatorState() {
        let animator = Animator(makeWriter: { AXWriter(pid: $0) }, applyFocus: { _, _ in })
        let window = Window(id: 4201, element: AXUIElementCreateApplication(-43), pid: -43, bundleID: nil)
        animator.position(window, at: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(animator.isBusy(window.id))
        animator.terminated(-43)
        animator.forget(window.id)
        #expect(!animator.isBusy(window.id))
        #expect(animator.activeWriterPids.isEmpty)
    }

    @Test func paddingAndGapsAreCapped() {
        let config = Config.parse("screen-padding-left = 5000\nwindow-margin-size = -5\n")
        #expect(config.paddingLeft == 500)
        #expect(config.windowMarginSize == 0)
        #expect(Config.parse("gaps_out = 9999\n").paddingBottom == 500)
        #expect(Config.parse("gaps_in = 80\n").windowMarginSize == 100)
        #expect(Config.parse("screen-padding-top = 24\n").paddingTop == 24)
    }

    @Test func paddingNeverGivesANegativeArea() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(WindowManager.padded(screen, left: 10, right: 10, top: 10, bottom: 10)
            == CGRect(x: 10, y: 10, width: 980, height: 780))
        let wide = WindowManager.padded(screen, left: 500, right: 500, top: 600, bottom: 200)
        #expect(wide == CGRect(x: 250, y: 300, width: 500, height: 400))
    }
}
