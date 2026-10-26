import Foundation

/// Makes Caps Lock send F18 while Minimal Cat runs, so the event tap sees a clean press and release.
/// It needs no permission, and macOS drops the mapping at restart.
public enum CapsMapping {
    private static let capsLock = 0x7_0000_0039
    private static let f18 = 0x7_0000_006D

    public enum Result: Equatable { case applied, othersMapping, failed }

    /// Leaves an existing mapping from another tool alone, because replacing it would break that tool.
    public static func apply() -> Result {
        let current = hidutil(["property", "--get", "UserKeyMapping"]) ?? ""
        let foreign = numbers(after: "HIDKeyboardModifierMappingSrc =", in: current).contains { $0 != capsLock }
            || numbers(after: "HIDKeyboardModifierMappingDst =", in: current).contains { $0 != f18 }
        if foreign { return .othersMapping }
        let mapping = "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":\(capsLock),"
            + "\"HIDKeyboardModifierMappingDst\":\(f18)}]}"
        return hidutil(["property", "--set", mapping]) == nil ? .failed : .applied
    }

    public static func remove() {
        _ = hidutil(["property", "--set", "{\"UserKeyMapping\":[]}"])
    }

    private static func numbers(after label: String, in output: String) -> [Int] {
        output.components(separatedBy: label).dropFirst().compactMap { part in
            Int(part.trimmingCharacters(in: .whitespaces).prefix(while: \.isNumber))
        }
    }

    private static func hidutil(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(bytes: data, encoding: .utf8) : nil
    }
}
