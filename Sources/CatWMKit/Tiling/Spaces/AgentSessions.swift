import Foundation

@MainActor package final class AgentSessions {
    private let make: () -> AgentDisplay?
    private var displays: [ObjectIdentifier: AgentDisplay] = [:]
    private var opening: Set<ObjectIdentifier> = []
    private var abandoned: Set<ObjectIdentifier> = []

    package init(make: @escaping () -> AgentDisplay? = { AgentDisplay() }) { self.make = make }

    package func open(for client: ControlConnection?) throws -> AgentDisplay {
        guard let client else { throw ControlError.failed("`agent.open` needs a connection") }
        let id = ObjectIdentifier(client)
        guard displays[id] == nil, !opening.contains(id) else {
            throw ControlError(code: "already_open", message: "This connection already has an agent display")
        }
        opening.insert(id)
        defer {
            opening.remove(id)
            abandoned.remove(id)
        }
        guard let display = make() else {
            throw ControlError(code: "unavailable", message: "macOS refused to create a virtual display")
        }
        guard !abandoned.contains(id) else {
            display.close()
            throw ControlError.failed("The connection closed while the agent display opened")
        }
        displays[id] = display
        return display
    }

    package func display(for client: ControlConnection?) throws -> AgentDisplay {
        guard let client, let display = displays[ObjectIdentifier(client)] else {
            throw ControlError(code: "not_open", message: "Run `agent.open` on this connection first")
        }
        return display
    }

    package func take(_ client: ControlConnection) -> AgentDisplay? {
        let id = ObjectIdentifier(client)
        if opening.contains(id) { abandoned.insert(id) }
        return displays.removeValue(forKey: id)
    }
}
