import Foundation
import Testing

@Test func checkStylePasses() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let pipe = Pipe()
    let process = Process()
    process.executableURL = root.appendingPathComponent("Tools/check-style.sh")
    process.currentDirectoryURL = root
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(process.terminationStatus == 0, "\(output)")
}
