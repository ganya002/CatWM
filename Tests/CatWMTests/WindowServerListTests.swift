import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WindowServerListTests {
    @Test func aCompleteListKeepsItsStackingOrder() {
        let found = WindowServerList.read(capacity: 4) { buffer in
            buffer[0] = 8; buffer[1] = 3; buffer[2] = 9
            return 3
        }
        #expect(found == [8, 3, 9])
    }

    @Test func anEmptyReplyRequiresThePublicFallback() {
        #expect(WindowServerList.read(capacity: 4, fill: { _ in 0 }) == nil)
    }

    @Test func aFullOrInvalidReplyRequiresThePublicFallback() {
        #expect(WindowServerList.read(capacity: 4, fill: { Int32($0.count) }) == nil)
        #expect(WindowServerList.read(capacity: 4, fill: { Int32($0.count) + 1 }) == nil)
        #expect(WindowServerList.read(capacity: 4, fill: { _ in -1 }) == nil)
        #expect(WindowServerList.read(capacity: 4, fill: { _ in nil }) == nil)
        #expect(WindowServerList.read(capacity: 4, fill: { _ in 1 }) == nil)
        let duplicate = WindowServerList.read(capacity: 4) { buffer in
            buffer[0] = 4; buffer[1] = 4
            return 2
        }
        #expect(duplicate == nil)
    }

    @Test func aPotentiallyTruncatedListRequiresThePublicFallback() {
        for returned: Int32 in [1_023, 1_024] {
            let found = WindowServerList.read(capacity: 1_024) { buffer in
                for index in 0..<Int(returned) { buffer[index] = CGWindowID(index + 1) }
                return returned
            }
            if returned == 1_024 {
                #expect(found == nil)
            } else {
                #expect(found?.count == 1_023 && found?.first == 1 && found?.last == 1_023)
            }
        }
    }

    @Test(arguments: [-1, 0, 65_536, Int32.max])
    func invalidCapacitiesDoNotAllocateOrReadTheServer(_ capacity: Int32) {
        let found = WindowServerList.read(capacity: capacity) { _ in
            Issue.record("Unexpected window list read")
            return 0
        }
        #expect(found == nil)
    }
}
