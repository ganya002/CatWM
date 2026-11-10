import Foundation

package enum ControlSchema {
    package static var commands: JSON { .array(CommandRegistry.published.map(describe)) }

    package static var document: JSON {
        [
            "protocol": .int(CommandRegistry.protocolVersion),
            "commands": commands,
            "events": .array(EventBus.specs.map { event in
                ["name": .string(event.name), "summary": .string(event.summary), "data": fields(event.data)]
            })
        ]
    }

    package static func write(in directory: URL) throws {
        let folder = directory.appendingPathComponent("Clients")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (document.encoded(pretty: true) + Data("\n".utf8)).write(to: folder.appendingPathComponent("schema.json"))
    }

    package static func describe(_ command: Command) -> JSON {
        let result: JSON
        switch command.result {
        case .none: result = ["kind": "none"]
        case .text: result = ["kind": "text"]
        case .value: result = ["kind": "value"]
        case .object(let list): result = ["kind": "object", "fields": fields(list)]
        case .list(let list): result = ["kind": "list", "fields": fields(list)]
        }
        return [
            "name": .string(command.name), "group": .string(command.group), "summary": .string(command.summary),
            "args": .array(command.args.map { arg in
                var entry: [String: JSON] = ["name": .string(arg.name), "type": .string(arg.kind.schemaName),
                                             "summary": .string(arg.summary), "required": .bool(arg.required)]
                if case .choice(let choices) = arg.kind { entry["choices"] = .array(choices.map(JSON.string)) }
                return .object(entry)
            }),
            "result": result
        ]
    }

    private static func fields(_ list: [Field]) -> JSON {
        .array(list.map { ["name": .string($0.name), "type": .string($0.type), "summary": .string($0.summary)] })
    }
}
