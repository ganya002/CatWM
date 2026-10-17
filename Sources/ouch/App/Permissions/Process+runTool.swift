import AppKit
import SwiftUI

extension Process {
    static func runTool(_ path: String, _ args: [String], wait: Bool = true) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        if wait { p.waitUntilExit() }
    }
}
