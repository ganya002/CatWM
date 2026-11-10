import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct HangCrashAuditTests {
    @Test func aTerminatedAppReleasesItsScanAndFocusQueues() {
        let scanner = WindowScanner(read: { _, _ in .init() }, readDesktop: { _ in WindowServerObservation() })
        scanner.run(-41) {}
        scanner.run(-42) {}
        scanner.terminated(-41)
        #expect(scanner.queueCount == 1)

        let reader = FocusReader(read: { _ in .focused(nil) })
        reader.observe(-41) { _ in }
        reader.terminated(-41)
        #expect(reader.queueCount == 0)
    }

    @Test func aTerminatedAppReleasesItsWriter() {
        let animator = Animator(makeWriter: { AXWriter(pid: $0) }, applyFocus: { _, _ in })
        let window = Window(id: 4101, element: AXUIElementCreateApplication(-41), pid: -41, bundleID: nil)
        animator.position(window, at: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(animator.activeWriterPids == [-41])
        animator.cancel(window.id)
        animator.terminated(-41)
        #expect(animator.activeWriterPids.isEmpty)
    }

    @Test func aHugeAnimationDurationIsCapped() {
        #expect(Config.parse("animation-duration = 1e12\n").animationDuration == 5)
        #expect(Config.parse("animation-duration = 250\n").animationDuration == 0.25)
    }

    @Test func aHugeMonitorStepDoesNotOverflow() {
        let manager = WindowManager(config: .parse(defaultText))
        guard let first = Screen.all().first else { return }
        #expect(manager.screen(from: first, spec: "+\(Int.max)", in: [first])?.uuid == first.uuid)
        #expect(manager.screen(from: first, spec: "-\(Int.max)", in: [first])?.uuid == first.uuid)
        #expect(manager.screen(from: first, spec: "+1", in: []) == nil)
    }
}
