@testable import CatWM
import Foundation
import Testing

@Suite struct ConfigWriteTests {
    @Test(arguments: ["smart-gaps", "follow_mouse", "new_is_master", "animations", "dim_inactive"], [false, true])
    func writingAnOptionUpdatesItsLastAlias(_ alias: String, _ hasCanonicalAssignment: Bool) throws {
        let option = try #require(ConfigOption.named(alias))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".conf")
        defer { Log.attempt("remove test config") { try FileManager.default.removeItem(at: url) } }
        let prefix = hasCanonicalAssignment ? "\(option.key) = false\n" : ""
        let bind = "bind = CTRL, h, movefocus, l\n"
        let comment = "# \(alias) = true\n"
        let original = prefix + bind + "\(alias.uppercased()) = true\n" + comment
        try original.write(to: url, atomically: true, encoding: .utf8)
        #expect(option.text(Config.parse(original)) == "true")

        Config.write(option: option.key, "false", to: url)

        let saved = try String(contentsOf: url, encoding: .utf8)
        let config = Config.parse(saved)
        #expect(config.errors.isEmpty)
        #expect(option.text(config) == "false")
        #expect(saved == prefix + bind + "\(option.key) = false\n" + comment)
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

        Config.write(option: "window-margins", "false", to: url)

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

        Config.write(option: "keyboard-help-key", "#", to: url)

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

        Config.write(option: "switcher-exclude", bundle, to: url)

        let config = Config.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(config.errors.isEmpty)
        #expect(config.switcherExclude == [bundle])
    }
}
