import AppKit

enum CommandRegistry {
    static let protocolVersion = 1

    static let all: [Command] = meta + dispatchers + state + config + development

    private static let byName = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    static func command(named name: String) -> Command? { byName[name.lowercased()] }

    static var published: [Command] { all.filter { $0.access == .public } }

    static func execute(_ name: String, _ args: [String: JSON], client: ControlConnection?,
                        manager: WindowManager = .shared) throws -> JSON {
        guard let command = command(named: name) else { throw ControlError.unknownCommand(name) }
        guard command.access != .keybindOnly else { throw ControlError.forbidden(name) }
        let call = try Invocation(args: command.validate(args), client: client, manager: manager)
        let target = command.name == "dispatch" ? call.text("dispatcher").lowercased() : command.name
        if let refusal = manager.scopeRefusal(target) { throw ControlError.failed(refusal) }
        return try command.run(call)
    }

    private static let meta: [Command] = [
        Command(name: "ping", group: "meta", summary: "Check that CatWM answers", result: .object([
            Field(name: "protocol", type: "int", summary: "Protocol version"),
            Field(name: "version", type: "string", summary: "CatWM version"),
            Field(name: "pid", type: "int", summary: "Process ID of CatWM")
        ])) { _ in ControlServer.hello },
        Command(name: "commands", group: "meta", summary: "List the commands with their arguments",
                result: .value) { _ in ControlSchema.commands },
        Command(name: "dispatch", group: "meta",
                summary: "Run a dispatcher by name, as a keybind does",
                args: [.text("dispatcher", "Dispatcher name"),
                       .text("arg", "Dispatcher argument", required: false)]) { call in
            let name = call.text("dispatcher").lowercased()
            guard dispatcherNames.contains(name) else {
                throw ControlError(code: "unknown_command", message: "Unknown dispatcher `\(name)`")
            }
            guard !keybindOnly.contains(name) else { throw ControlError.forbidden(name) }
            call.manager.dispatch(name, call.text("arg"))
            return .null
        },
        Command(name: "subscribe", group: "events", summary: "Receive events on this connection",
                args: [eventsArg], result: .object([
                    Field(name: "events", type: "string[]", summary: "Events that this connection receives")
                ])) { call in
            guard let client = call.client else { throw ControlError.failed("`subscribe` needs a connection") }
            let names = try EventBus.names(call.args["events"])
            return ["events": .array(EventBus.shared.subscribe(client, to: names).map(JSON.string))]
        },
        Command(name: "unsubscribe", group: "events", summary: "Stop receiving events on this connection",
                args: [eventsArg], result: .object([
                    Field(name: "events", type: "string[]", summary: "Events that this connection still receives")
                ])) { call in
            guard let client = call.client else { throw ControlError.failed("`unsubscribe` needs a connection") }
            let names = try EventBus.names(call.args["events"])
            return ["events": .array(EventBus.shared.unsubscribe(client, from: names).map(JSON.string))]
        }
    ]

    private static let eventsArg = CommandArg(
        name: "events", kind: .strings,
        summary: "Event names. An empty list means every event.", required: false
    )

    private static let development: [Command] = [
        Command(name: "grabtest", group: "dev", summary: "Run the window grab test", access: .dev) { call in
            call.manager.grabTest()
            return .null
        },
        Command(name: "poststyle", group: "dev", summary: "Set the key post style",
                args: [CommandArg(name: "style", kind: .int, summary: "Style number")], access: .dev) { call in
            if let style = call.args["style"]?.int.flatMap(Hotkeys.PostStyle.init(rawValue:)) {
                call.manager.keyPostStyle = style
            }
            Log.info("ipc: post style is now \(call.manager.keyPostStyle)")
            return .null
        },
        Command(name: "modefx", group: "dev", summary: "Preview a mode effect",
                args: [.text("style", "Effect name or `all`", required: false)], access: .dev) { call in
            ModeFX.shared.command(call.text("style").split(separator: " ").map(String.init))
            return .null
        },
        Command(name: "panelfx", group: "dev", summary: "Preview a panel motion",
                args: [.text("style", "Motion name or `all`", required: false)], access: .dev) { call in
            PanelMotionDemo.shared.command(call.text("style").split(separator: " ").map(String.init))
            return .null
        },
        Command(name: "intro", group: "dev", summary: "Play the intro",
                args: [.text("arrangement", "Arrangement name", required: false)], access: .dev) { call in
            Onboarding.shared.playIntro(IntroScore.Arrangement.named(call.text("arrangement")) ?? .standard)
            return .null
        },
        Command(name: "introlab", group: "dev", summary: "Open the intro lab", access: .dev) { _ in
            IntroLab.shared.open()
            return .null
        }
    ]
}
