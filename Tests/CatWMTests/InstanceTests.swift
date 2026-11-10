@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct InstanceTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-instance-\(UUID().uuidString)")

    @Test func theDefaultInstanceKeepsTheOldPaths() throws {
        let paths = try #require(InstancePaths(id: nil, home: home))
        #expect(paths.configFolder == home.appendingPathComponent(".config/catwm"))
        #expect(paths.logURL == home.appendingPathComponent("Library/Logs/CatWM.log"))
        #expect(paths.supportFolder == home.appendingPathComponent("Library/Application Support/CatWM"))
        #expect(paths.cacheFolder == home.appendingPathComponent("Library/Caches/catwm"))
        #expect(paths.pidFile == home.appendingPathComponent(".config/catwm/catwm.pid"))
        #expect(paths.defaultsSuite == nil)
    }

    @Test func aNamedInstanceKeepsEachPathInItsOwnFolder() throws {
        let paths = try #require(InstancePaths(id: "verify-a1", home: home))
        for folder in [paths.configFolder, paths.supportFolder, paths.cacheFolder] {
            #expect(folder.path.hasSuffix("/instances/verify-a1"))
        }
        #expect(paths.configFolder == home.appendingPathComponent(".config/catwm/instances/verify-a1"))
        #expect(paths.pidFile.deletingLastPathComponent().path == paths.configFolder.path)
        #expect(paths.logURL == home.appendingPathComponent("Library/Logs/CatWM-verify-a1.log"))
        #expect(paths.defaultsSuite == "local.catwm.instance.verify-a1")
    }

    @Test(arguments: ["", "Dev", "a/b", "..", "a b", "ä", String(repeating: "a", count: 25)])
    func aBadIdIsRefused(_ id: String) {
        #expect(InstancePaths(id: id, home: home) == nil)
    }

    @Test func aLongValidIdIsAccepted() {
        #expect(InstancePaths(id: String(repeating: "a", count: 24), home: home) != nil)
    }

    @Test func theDefaultInstanceSkipsThePidsOfNamedInstances() throws {
        let paths = try #require(InstancePaths(id: nil, home: home))
        let other = try #require(InstancePaths(id: "other", home: home))
        try FileManager.default.createDirectory(at: other.configFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("42\n".utf8).write(to: other.pidFile)
        let named = Set(paths.namedPidFiles().compactMap(InstancePaths.readPid))
        #expect(named == [42])
        let pids = InstancePaths.pidsToClose(own: 1, named: false, recorded: 7, running: [1, 7, 9, 42],
                                             otherInstances: named)
        #expect(pids == [7, 9])
    }

    @Test func aNamedInstanceClosesOnlyItsRecordedPid() {
        #expect(InstancePaths.pidsToClose(own: 1, named: true, recorded: 7, running: [1, 7, 9],
                                          otherInstances: []) == [7])
        #expect(InstancePaths.pidsToClose(own: 1, named: true, recorded: 8, running: [1, 7, 9],
                                          otherInstances: []).isEmpty)
        #expect(InstancePaths.pidsToClose(own: 1, named: true, recorded: 1, running: [1],
                                          otherInstances: []).isEmpty)
    }

    @Test func aNamedInstanceDoesNotListItsOwnPidFile() throws {
        let paths = try #require(InstancePaths(id: "mine", home: home))
        try FileManager.default.createDirectory(at: paths.configFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(paths.namedPidFiles().isEmpty)
    }

    @Test func theSocketRefusesAPathThatIsTooLong() {
        let folder = "/tmp/catwm-test-\(UUID().uuidString)/" + String(repeating: "a", count: 80)
        var lines: [String] = []
        #expect(ControlServer.listen(on: folder + "/catwm.sock") { lines.append($0) } == nil)
        #expect(!FileManager.default.fileExists(atPath: folder))
        #expect(lines.count == 1 && lines[0].contains("too long"))
    }

    @Test func aNamedInstanceDoesNotChangeTheLoginItem() {
        var calls: [Bool] = []
        #expect(!LoginItem.shared.set(true, available: false) { calls.append($0) })
        #expect(!LoginItem.shared.set(false, available: false) { calls.append($0) })
        #expect(calls.isEmpty)
    }
}
