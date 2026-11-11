import AppKit
@testable import CatWMKit
import Testing

@MainActor @Suite struct AgentCommandTests {
    let names = ["agent.open", "agent.launch", "agent.windows", "agent.type", "agent.key", "agent.press", "agent.text",
                 "agent.screenshot", "agent.close"]

    func connection() -> (ControlConnection, Int32) {
        var pair: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &pair)
        return (ControlConnection(descriptor: pair[0], onLine: { _, _ in }, onClose: { _ in }), pair[1])
    }

    func answer(_ text: String, client: ControlConnection?) async -> JSON {
        let data = await withCheckedContinuation { next in
            ControlServer.respond(to: Data(text.utf8), client: client) { next.resume(returning: $0) }
        }
        return JSON.parse(data) ?? .null
    }

    @Test func theAgentCommandsArePublicAndLaunchAndExecStayKeybindOnly() {
        for name in names {
            #expect(CommandRegistry.command(named: name)?.access == .public, "\(name)")
            #expect(WindowScope.allowedCommands.contains(name))
        }
        #expect(CommandRegistry.command(named: "launch")?.access == .keybindOnly)
        #expect(CommandRegistry.command(named: "exec")?.access == .keybindOnly)
    }

    @Test func aCommandBeforeOpenFailsWithNotOpen() async {
        for name in ["agent.windows", "agent.launch"] {
            let args = name == "agent.launch" ? #","args":{"app":"com.apple.TextEdit"}"# : ""
            let reply = await answer(#"{"id":1,"command":"\#(name)"\#(args)}"#, client: nil)
            #expect(reply.object?["ok"] == false)
            #expect(reply.object?["error"]?.object?["code"]?.string == "not_open", "\(name)")
        }
        let closed = await answer(#"{"id":2,"command":"agent.close"}"#, client: nil)
        #expect(closed.object?["ok"] == true)
    }

    @Test func aConnectionOwnsOneDisplayAndTakingItEndsTheOwnership() throws {
        let world = AgentDisplayTests.World()
        let sessions = AgentSessions { world.display() }
        let (client, other) = connection()
        defer { Darwin.close(other) }
        #expect(throws: ControlError.self) { try sessions.open(for: nil) }
        #expect(throws: ControlError.self) { try sessions.display(for: client) }
        let display = try sessions.open(for: client)
        #expect(try sessions.display(for: client) === display)
        #expect(throws: ControlError(code: "already_open", message: "This connection already has an agent display")) {
            try sessions.open(for: client)
        }
        #expect(sessions.take(client) === display)
        #expect(sessions.take(client) == nil)
    }

    @Test func aConnectionThatClosesWhileTheDisplayOpensDoesNotLeakIt() throws {
        let world = AgentDisplayTests.World()
        let (client, other) = connection()
        defer { Darwin.close(other) }
        final class Slot { var sessions: AgentSessions? }
        let slot = Slot()
        var made: AgentDisplay?
        var secondOpenRefused = false
        let sessions = AgentSessions {
            secondOpenRefused = (try? slot.sessions?.open(for: client)) == nil
            _ = slot.sessions?.take(client)
            made = world.display()
            return made
        }
        slot.sessions = sessions
        #expect(throws: ControlError.self) { try sessions.open(for: client) }
        #expect(secondOpenRefused)
        #expect(made?.bounds == .zero)
        #expect(throws: ControlError.self) { try sessions.display(for: client) }
    }

    @Test func aMissingVirtualDisplayReportsUnavailable() throws {
        let sessions = AgentSessions { nil }
        let (client, other) = connection()
        defer { Darwin.close(other) }
        #expect(throws: ControlError.self) { try sessions.open(for: client) }
    }

    @Test func anUnknownKeyOrModifierIsRefusedBeforeAnyEventIsPosted() {
        #expect(throws: ControlError.self) { try AgentWindowIO.press("hyper+a", pid: 1) }
        #expect(throws: ControlError.self) { try AgentWindowIO.press("cmd+nope", pid: 1) }
    }
}
