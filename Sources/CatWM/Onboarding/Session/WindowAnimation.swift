import AppKit
import SwiftUI

extension NSWindow.Level {
    static func above(_ level: NSWindow.Level, _ offset: Int) -> NSWindow.Level {
        NSWindow.Level(rawValue: level.rawValue + offset)
    }
}
