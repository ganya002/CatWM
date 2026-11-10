@testable import CatWM
@testable import CatWMKit
import SwiftUI
import Testing

@Suite struct NotchShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)
    private let insideNotch = CGPoint(x: 500, y: 20)
    private let besideNotch = CGPoint(x: 700, y: 20)

    @Test func fillCoversOnlyTheNotch() {
        let path = NotchFill(halfWidth: 100, height: 32).path(in: rect)
        #expect(path.contains(insideNotch))
        #expect(!path.contains(besideNotch))
    }

    @Test func cutoutExcludesTheNotch() {
        let path = NotchCutout(halfWidth: 100, height: 32).path(in: rect)
        #expect(!path.contains(insideNotch, eoFill: true))
        #expect(path.contains(besideNotch, eoFill: true))
    }

    @Test func aScreenWithoutANotchFillsNothing() {
        #expect(NotchFill(halfWidth: 0, height: 0).path(in: rect).isEmpty)
        #expect(NotchCutout(halfWidth: 0, height: 0).path(in: rect).contains(insideNotch, eoFill: true))
    }
}
