import AppKit
@testable import ouch
import Testing

@Suite struct WindowServerListTests {
    @Test func windowsCreatedAfterTheCountReadKeepTheirStackingOrder() {
        let found = WindowServerList.read(count: 1) { buffer in
            buffer[0] = 8; buffer[1] = 3; buffer[2] = 9
            return 3
        }
        #expect(found == [8, 3, 9])
        #expect(WindowServerList.read(count: 3, fill: { _ in 0 })?.isEmpty == true)
    }

    @Test func aFullOrInvalidReplyRequiresThePublicFallback() {
        #expect(WindowServerList.read(count: 1, fill: { Int32($0.count) }) == nil)
        #expect(WindowServerList.read(count: 1, fill: { Int32($0.count) + 1 }) == nil)
        #expect(WindowServerList.read(count: 1, fill: { _ in -1 }) == nil)
        #expect(WindowServerList.read(count: 1, fill: { _ in nil }) == nil)
        #expect(WindowServerList.read(count: 1, fill: { _ in 1 }) == nil)
        let duplicate = WindowServerList.read(count: 2) { buffer in
            buffer[0] = 4; buffer[1] = 4
            return 2
        }
        #expect(duplicate == nil)
    }

    @Test(arguments: [-1, 65_536, Int32.max])
    func invalidCountsDoNotAllocateOrReadTheServer(_ count: Int32) {
        let found = WindowServerList.read(count: count) { _ in
            Issue.record("Unexpected window list read")
            return 0
        }
        #expect(found == nil)
    }
}
