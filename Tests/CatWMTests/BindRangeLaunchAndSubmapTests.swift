@testable import CatWM
import Foundation
import Testing

@Test func launchKeepsAURLWithTwoDots() throws {
    let url = "https://github.com/a/b/compare/main..dev"
    let pairs = try BindRange.pairs(key: "G", dispatcher: "launch", arg: url).get()
    #expect(pairs.map(\.arg) == [url])
}

@Test func launchKeepsAPathRangeThatDoesNotMatchTheKeys() throws {
    let pairs = try BindRange.pairs(key: "T", dispatcher: "launch", arg: "~/Code/a|b").get()
    #expect(pairs.map(\.arg) == ["~/Code/a|b"])
}

@Test func launchStillSpreadsAppsOverAKeyRange() throws {
    let pairs = try BindRange.pairs(key: "1|2", dispatcher: "launch", arg: "Safari|Mail").get()
    #expect(pairs.map(\.key) == ["1", "2"])
    #expect(pairs.map(\.arg) == ["Safari", "Mail"])
}

@Test func otherDispatchersStillReportABadRange() {
    guard case .failure = BindRange.pairs(key: "1..3", dispatcher: "workspace", arg: "a..b1") else {
        Issue.record("expected a failure")
        return
    }
}

@Test func submapWithNoBindsIsAConfigError() {
    let config = Config.parse("""
    bind = CTRL, W, submap, Window
    submap = window
    bind = , H, movefocus, l
    submap = reset
    """)
    #expect(config.errors == ["`submap, Window` enters a mode with no binds (did you mean `window`?)"])
}

@Test func submapWithBindsIsNoError() {
    let config = Config.parse("""
    bind = CTRL, W, submap, window
    submap = window
    bind = , escape, submap, reset
    submap = reset
    """)
    #expect(config.errors.isEmpty)
}

@Test func hotkeysStayOutOfAModeWithNoBinds() {
    let hotkeys = Hotkeys()
    hotkeys.setBindings(Config.parse("submap = window\nbind = , H, movefocus, l\nsubmap = reset").bindings)
    hotkeys.setSubmap("Window")
    #expect(hotkeys.submap.isEmpty)
    hotkeys.setSubmap("window")
    #expect(hotkeys.submap == "window")
}

@Test func logTailStartsOnAFullLine() {
    let line = Data(String(repeating: "x", count: 99).utf8) + Data("\n".utf8)
    let data = Data((0..<(Log.keptSize / 100 + 10)).flatMap { _ in line })
    let tail = Log.tail(of: data)
    #expect(tail.count <= Log.keptSize)
    #expect(tail.first == UInt8(ascii: "x"))
    #expect(tail.count.isMultiple(of: 100))
    #expect(Log.tail(of: line) == line)
}

@Test func testsLogToATemporaryFile() throws {
    let real = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CatWM.log")
    let marker = "log test \(UUID().uuidString)"
    Log.info(marker)
    #expect(Log.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    #expect(try String(contentsOf: Log.url, encoding: .utf8).contains(marker))
    let realText = (try? String(contentsOf: real, encoding: .utf8)) ?? ""
    #expect(!realText.contains(marker))
}

@Test func numberRowRangeCanRunBackwards() throws {
    let pairs = try BindRange.pairs(key: "0..1", dispatcher: "workspace", arg: "10..1").get()
    #expect(pairs.map(\.key) == ["0", "9", "8", "7", "6", "5", "4", "3", "2", "1"])
    #expect(pairs.map(\.arg) == ["10", "9", "8", "7", "6", "5", "4", "3", "2", "1"])
}
