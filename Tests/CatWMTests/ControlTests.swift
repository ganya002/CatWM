@testable import CatWM
import Foundation
import Testing

private var projectRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func reply(_ text: String) throws -> JSON {
    try #require(JSON.parse(ControlServer.reply(to: Data(text.utf8), client: nil)))
}

@Suite struct ControlRegistryTests {
    @Test func cliPreservesOptionsAfterSeparator() throws {
        let parsed = ControlCLI.options(["--json", "config.set", "some-key", "--", "tool", "--json"])
        #expect(parsed.compact)
        let command = try #require(CommandRegistry.command(named: "config.set"))
        let args = try ControlCLI.bind(Array(parsed.words.dropFirst()), to: command)
        #expect(args == ["key": "some-key", "value": "tool --json"])
        #expect(!ControlCLI.options(["config.set", "some-key", "--", "tool", "--json"]).compact)
    }

    @Test func everyDispatcherCanBeCalledThroughTheRegistry() {
        let missing = WindowActions.all.map(\.name).filter { CommandRegistry.command(named: $0) == nil }
        #expect(missing.isEmpty)
    }

    @Test func commandNamesAreUnique() {
        let names = CommandRegistry.all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func keybindOnlyCommandsAreRefused() throws {
        for name in ["exec", "launch"] {
            let answer = try reply(#"{"id":1,"command":"\#(name)","args":{}}"#)
            #expect(answer["ok"] == .bool(false))
            #expect(answer["error"]?["code"] == "forbidden")
        }
        let viaDispatch = try reply(#"{"id":2,"command":"dispatch","args":{"dispatcher":"exec","arg":"true"}}"#)
        #expect(viaDispatch["error"]?["code"] == "forbidden")
    }

    @Test func badRequestsGetTypedErrors() throws {
        #expect(try reply("not json")["error"]?["code"] == "bad_request")
        #expect(try reply(#"{"id":3}"#)["error"]?["code"] == "bad_request")
        #expect(try reply(#"{"id":4,"command":"nothing"}"#)["error"]?["code"] == "unknown_command")
        #expect(try reply(#"{"id":5,"command":"movefocus","args":{}}"#)["error"]?["code"] == "invalid_args")
        #expect(try reply(#"{"id":6,"command":"movefocus","args":{"direction":"sideways"}}"#)["error"]?["code"]
                == "invalid_args")
        #expect(try reply(#"{"id":7,"command":"movefocus","args":{"direction":"left","extra":1}}"#)["error"]?["code"]
                == "invalid_args")
    }

    @Test func dispatchRefusesAnUnknownDispatcher() throws {
        for name in ["mvoefocus", "status", ""] {
            let answer = try reply(#"{"id":1,"command":"dispatch","args":{"dispatcher":"\#(name)","arg":"left"}}"#)
            #expect(answer["error"]?["code"] == "unknown_command", "\(name)")
        }
    }

    @Test func dispatchKnowsAliasesAndFocusFeatures() {
        let names = ["setlayout", "reevaluate"] + FocusDim.features.map(\.pointer.dispatcher)
        #expect(names.allSatisfy(CommandRegistry.dispatcherNames.contains))
    }

    @Test func hugeNumbersAreRefusedNotTrapped() throws {
        let answer = try reply(#"{"id":1,"command":"poststyle","args":{"style":1e100}}"#)
        #expect(answer["error"]?["code"] == "invalid_args")
    }

    @Test func aConfigValueCannotAddLines() throws {
        let value = "com.example.App\\nbind = SUPER, F12, exec, /usr/bin/touch /tmp/catwm-injected"
        let line = #"{"id":1,"command":"config.set","args":{"key":"switcher-exclude","value":"\#(value)"}}"#
        let answer = try reply(line)
        #expect(answer["error"]?["code"] == "invalid_args")
    }

    @Test func theAnswerKeepsTheRequestID() throws {
        let answer = try reply(#"{"id":"abc","command":"ping"}"#)
        #expect(answer["id"] == "abc")
        #expect(answer["ok"] == true)
        #expect(answer["result"]?["protocol"] == .int(CommandRegistry.protocolVersion))
    }

    @Test func choicesIgnoreCase() throws {
        let command = try #require(CommandRegistry.command(named: "movefocus"))
        #expect(try command.validate(["direction": "LEFT"]) == ["direction": "left"])
    }

    @Test func positionalWordsBindToArguments() throws {
        let layoutmsg = try #require(CommandRegistry.command(named: "layoutmsg"))
        #expect(try ControlCLI.bind(["mfact", "0.1"], to: layoutmsg) == ["message": "mfact 0.1"])
        let set = try #require(CommandRegistry.command(named: "config.set"))
        #expect(try ControlCLI.bind(["gaps-in", "8"], to: set) == ["key": "gaps-in", "value": "8"])
        let focus = try #require(CommandRegistry.command(named: "movefocus"))
        #expect(throws: ControlError.self) { try ControlCLI.bind(["left", "right"], to: focus) }
    }

    @Test func theSchemaFileMatchesTheRegistry() throws {
        let file = projectRoot.appendingPathComponent("Clients/schema.json")
        let stored = try Data(contentsOf: file)
        let expected = ControlSchema.document.encoded(pretty: true) + Data("\n".utf8)
        #expect(stored == expected, "Run ./build.sh --dev")
    }

    @Test func devCommandsStayOutOfTheSchema() {
        let published = Set(CommandRegistry.published.map(\.name))
        #expect(published.isDisjoint(with: ["grabtest", "poststyle", "modefx", "panelfx", "intro", "introlab"]))
        #expect(!published.contains("exec") && !published.contains("launch"))
    }
}

@Suite struct ControlEventTests {
    @Test func aDiffNamesEachChange() {
        var old = StateSnapshot()
        old.windows = [1: .init(app: "a", title: "one")]
        old.focused = 1
        old.workspaces = ["d": "1"]
        var new = old
        new.windows = [2: .init(app: "b", title: "two")]
        new.focused = 2
        new.workspaces = ["d": "2"]
        new.mode = "window"
        let names = EventBus.changes(from: old, to: new).map(\.0)
        #expect(names == ["window.added", "window.removed", "focus.changed", "workspace.changed", "mode.changed"])
    }

    @Test func noChangeMakesNoEvent() {
        let snapshot = StateSnapshot()
        #expect(EventBus.changes(from: snapshot, to: snapshot).isEmpty)
    }

    @Test func unknownEventNamesAreRefused() throws {
        #expect(throws: ControlError.self) { try EventBus.names(["nothing"]) }
        #expect(try EventBus.names(nil) == EventBus.allNames)
    }
}

@Suite(.serialized) struct ControlSocketTests {
    @Test(arguments: [ControlConnection.maxLine, ControlConnection.maxLine + 1])
    func completeLinesRespectTheSizeLimit(length: Int) throws {
        var descriptors: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let sender = descriptors[0]
        defer { Darwin.close(sender) }
        var quiet: Int32 = 1
        setsockopt(sender, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
        let closed = DispatchSemaphore(value: 0)
        let delivered = DispatchSemaphore(value: 0)
        let connection = ControlConnection(descriptor: descriptors[1], onLine: { connection, line in
            delivered.signal()
            #expect(length <= ControlConnection.maxLine, "An oversized line reached the command handler")
            #expect(line.count == length)
            connection.close()
        }, onClose: { _ in closed.signal() })
        connection.start()
        defer { connection.close() }
        let data = Data(repeating: 0x61, count: length) + Data([0x0A])
        var sent = 0
        while sent < data.count {
            let count = data.withUnsafeBytes { write(sender, $0.baseAddress?.advanced(by: sent), $0.count - sent) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            sent += count
        }
        #expect(closed.wait(timeout: .now() + 5) == .success)
        #expect((delivered.wait(timeout: .now()) == .success) == (length <= ControlConnection.maxLine))
    }

    private func makePath() -> String {
        "/tmp/catwm-test-\(UInt32.random(in: 0...UInt32.max)).sock"
    }

    @Test func aClientCanCallACommandOverTheSocket() throws {
        let path = makePath()
        let server = ControlServer()
        server.start(path: path)
        defer { server.stop() }
        let client = try #require(ControlCLI.Client(path: path))
        client.setTimeout(seconds: 60)
        let pong = client.call("ping", [:])
        #expect(pong["ok"] == true)
        #expect(pong["result"]?["pid"] == .int(Int(getpid())))
        let bad = client.call("movefocus", ["direction": "nowhere"])
        #expect(bad["ok"] == false)
        let mode = try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        #expect(mode == 0o600)
    }

    @Test func aSecondServerLeavesTheFirstAlone() throws {
        let path = makePath()
        let first = ControlServer(), second = ControlServer()
        first.start(path: path)
        defer { first.stop() }
        second.start(path: path)
        defer { second.stop() }
        let client = try #require(ControlCLI.Client(path: path))
        client.setTimeout(seconds: 60)
        #expect(client.call("ping", [:])["ok"] == true)
    }

    @Test func aSubscriberReceivesOnlyTheEventsItAskedFor() throws {
        let path = makePath()
        let server = ControlServer()
        server.start(path: path)
        defer { server.stop() }
        let client = try #require(ControlCLI.Client(path: path))
        client.setTimeout(seconds: 60)
        let answer = client.call("subscribe", ["events": ["tiling.changed"]])
        #expect(answer["result"]?["events"] == ["tiling.changed"])
        DispatchQueue.main.sync {
            EventBus.shared.emit("mode.changed", ["mode": "window"])
            EventBus.shared.emit("tiling.changed", ["enabled": false])
        }
        let event = try #require(client.readLine().flatMap(JSON.parse))
        #expect(event["event"] == "tiling.changed")
        #expect(event["data"]?["enabled"] == false)
        let ended = client.call("unsubscribe", [:])
        #expect(ended["result"]?["events"] == .array([]))
    }
}
