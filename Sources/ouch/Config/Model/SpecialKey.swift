import AppKit

enum SpecialKey {
    static let mouseUp: UInt16 = 0x1000, mouseDown: UInt16 = 0x1001
    static let mouseLeft: UInt16 = 0x1002, mouseRight: UInt16 = 0x1003
    static let swipeLeft: UInt16 = 0x1010, swipeRight: UInt16 = 0x1011
    static let swipeUp: UInt16 = 0x1012, swipeDown: UInt16 = 0x1013
    static func isScroll(_ code: UInt16) -> Bool { (0x1000...0x1003).contains(code) }
    static func isSwipe(_ code: UInt16) -> Bool { (0x1010...0x1013).contains(code) }
}
