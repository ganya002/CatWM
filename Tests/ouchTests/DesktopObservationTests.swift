import AppKit
import Testing
@testable import ouch

@Suite struct DesktopObservationTests {
    @Test @MainActor func eventsDuringADesktopReadProduceOneFreshFollowUp() async {
        let release = DispatchSemaphore(value: 0)
        let reads = FocusObservationTests.Counter()
        let scanner = WindowScanner(readDesktop: { known in
            #expect(!Thread.isMainThread)
            if reads.next() == 1 { _ = release.wait(timeout: .now() + 3) }
            return WindowServerObservation(spaces: Dictionary(uniqueKeysWithValues: known.map { ($0, Set<UInt64>([1])) }))
        })
        var firstCompleted = false
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: [1]) { firstCompleted = true }
            for id in CGWindowID(2)...51 {
                scanner.observeDesktop(known: [id]) {
                    #expect(id == 51)
                    continuation.resume()
                }
            }
            release.signal()
        }
        #expect(firstCompleted)
        #expect(reads.value == 2)
        #expect(Set(scanner.desktop.spaces.keys) == Set(CGWindowID(2)...51))
    }
}
