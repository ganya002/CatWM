import AppKit
import SwiftUI

extension NSWindow.Level {
    static func above(_ l: NSWindow.Level, _ n: Int) -> NSWindow.Level { NSWindow.Level(rawValue: l.rawValue + n) }
}
