@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct MigrationsTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-migrations-\(UUID().uuidString)")

    func write(_ text: String, _ path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: home.appendingPathComponent(path), encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path)
    }

    @Test func movesOuchFilesAndRenamesTheConfig() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("conf", ".config/ouch/ouch.conf")
        try write("[]", ".config/ouch/templates.json")
        try write("sock", ".config/ouch/ouch.sock")
        Migrations.moveOuchConfigFolder(home: home)
        #expect(read(".config/catwm/catwm.conf") == "conf")
        #expect(read(".config/catwm/templates.json") == "[]")
        #expect(!exists(".config/catwm/ouch.sock"))
        #expect(!exists(".config/ouch"))
    }

    @Test func neverReplacesACatWMFile() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("old", ".config/ouch/ouch.conf")
        try write("new", ".config/catwm/catwm.conf")
        Migrations.moveOuchConfigFolder(home: home)
        #expect(read(".config/catwm/catwm.conf") == "new")
        #expect(read(".config/ouch/ouch.conf") == "old")
    }

    @Test func runsTwiceWithTheSameResult() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("conf", ".config/ouch/ouch.conf")
        Migrations.moveOuchConfigFolder(home: home)
        Migrations.moveOuchConfigFolder(home: home)
        #expect(read(".config/catwm/catwm.conf") == "conf")
    }

    @Test func doesNothingWithoutAnOuchFolder() {
        defer { try? FileManager.default.removeItem(at: home) }
        Migrations.moveOuchConfigFolder(home: home)
        #expect(!exists(".config/catwm"))
    }

    @Test func hyprthystConfigFillsAnEmptyCatWMFolder() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("hypr", ".config/hyprthyst/hyprthyst.conf")
        Migrations.copyHyprthystConfig(home: home)
        #expect(read(".config/catwm/catwm.conf") == "hypr")
        #expect(read(".config/hyprthyst/hyprthyst.conf") == "hypr")
    }

    @Test func ouchConfigWinsOverHyprthyst() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("ouch", ".config/ouch/ouch.conf")
        try write("hypr", ".config/hyprthyst/hyprthyst.conf")
        Migrations.moveOuchConfigFolder(home: home)
        Migrations.copyHyprthystConfig(home: home)
        #expect(read(".config/catwm/catwm.conf") == "ouch")
    }

    @Test func recognisesLegacyBundles() {
        #expect(Legacy.isBundle("local.ouch"))
        #expect(Legacy.isBundle("local.hyprthyst"))
        #expect(!Legacy.isBundle("com.apple.finder"))
    }
}
