import AppKit
import SwiftUI

extension Process {
    static func runTool(_ path: String, _ args: [String], wait: Bool = true) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        if wait { process.waitUntilExit() }
    }
}
