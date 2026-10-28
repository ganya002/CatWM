@testable import CatWM
import Foundation
import Testing

@Suite struct ConfigWriteTests {
    @Test func anUnreadableConfigReportsAnErrorAndKeepsItsContents() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".conf")
        defer { Log.attempt("remove test config") { try FileManager.default.removeItem(at: url) } }
        let original = Data([0xFF])
        try original.write(to: url)

        #expect(throws: (any Error).self) { try Config.write(option: "window-margins", "false", to: url) }

        #expect(try Data(contentsOf: url) == original)
    }

    @Test func aFailedWriteReportsAnError() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("catwm.conf")

        #expect(throws: (any Error).self) { try Config.write(option: "window-margins", "false", to: url) }

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [
        "window-margins = false\nwindow-margins = true\n",
        "window-margins = false\nWINDOW_MARGINS = true\n",
        "window-margins = false\nwindow-margins = true\n# window-margins = true\n"
    ])
    func writingAnOptionUpdatesTheLastAssignment(_ original: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".conf")
        defer { Log.attempt("remove test config") { try FileManager.default.removeItem(at: url) } }
        try original.write(to: url, atomically: true, encoding: .utf8)
        #expect(Config.parse(original).windowMargins)

        try Config.write(option: "window-margins", "false", to: url)

        let saved = try String(contentsOf: url, encoding: .utf8)
        let config = Config.parse(saved)
        #expect(config.errors.isEmpty)
        #expect(!config.windowMargins)
        #expect(saved.hasPrefix("window-margins = false\n"))
        #expect(saved.hasSuffix("# window-margins = true\n") == original.hasSuffix("# window-margins = true\n"))
    }

    @Test(arguments: ["keyboard-help-key = ?\n", "keyboard_help_key = ?\n", "window-margins = false\n"])
    func writingAHashKeepsTheCharacter(_ original: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".conf")
        defer { Log.attempt("remove test config") { try FileManager.default.removeItem(at: url) } }
        try original.write(to: url, atomically: true, encoding: .utf8)

        try Config.write(option: "keyboard-help-key", "#", to: url)

        let saved = try String(contentsOf: url, encoding: .utf8)
        let config = Config.parse(saved)
        #expect(config.errors.isEmpty)
        #expect(config.keyboardHelpKey == "#")
        #expect(config.windowMargins == Config.parse(original).windowMargins)
    }

    @Test(arguments: ["com.example.#app", "com.example.##app"])
    func writingAListKeepsEveryHash(_ bundle: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".conf")
        defer { Log.attempt("remove test config") { try FileManager.default.removeItem(at: url) } }
        try "switcher-exclude = com.example.old\n".write(to: url, atomically: true, encoding: .utf8)

        try Config.write(option: "switcher-exclude", bundle, to: url)

        let config = Config.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(config.errors.isEmpty)
        #expect(config.switcherExclude == [bundle])
    }
}
