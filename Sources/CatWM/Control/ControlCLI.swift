import Foundation

enum ControlCLI {
    static func run(_ arguments: [String]) -> Never {
        signal(SIGPIPE, SIG_IGN)
        let (words, compact) = options(arguments)
        guard let name = words.first?.lowercased() else { finish(help(nil), code: 0) }
        let rest = Array(words.dropFirst())
        if name == "help" || name == "--help" || name == "-h" { finish(help(rest.first), code: 0) }
        if name == "events" { stream(rest) }
        guard let command = CommandRegistry.command(named: name), command.access != .keybindOnly else {
            let known = CommandRegistry.command(named: name) != nil
            fail(known ? ControlError.forbidden(name).message : ControlError.unknownCommand(name).message
                + ". Run `catwm help` to see the commands.", code: 2)
        }
        let args: [String: JSON]
        do {
            args = try bind(rest, to: command)
        } catch let error as ControlError {
            fail(error.message, code: 2)
        } catch {
            fail("\(error)", code: 2)
        }
        let connection = connect()
        let response = connection.call(name, args)
        guard response["ok"]?.isTrue == true else {
            fail(response["error"]?["message"]?.string ?? "CatWM did not answer", code: 1)
        }
        finish(render(response["result"] ?? .null, compact: compact), code: 0)
    }

    static func options(_ arguments: [String]) -> (words: [String], compact: Bool) {
        var words: [String] = []
        var compact = false
        var literal = false
        for argument in arguments {
            if !literal && argument == "--" { literal = true; continue }
            if !literal && argument == "--json" { compact = true; continue }
            words.append(argument)
        }
        return (words, compact)
    }

    static func bind(_ words: [String], to command: Command) throws -> [String: JSON] {
        var args: [String: JSON] = [:]
        var rest = words[...]
        for (index, arg) in command.args.enumerated() {
            guard !rest.isEmpty else { break }
            let isLast = index == command.args.count - 1
            switch arg.kind {
            case .strings:
                args[arg.name] = .array(rest.map(JSON.string))
                rest = []
            case .string where isLast:
                args[arg.name] = .string(rest.joined(separator: " "))
                rest = []
            case .int:
                guard let number = Int(rest.removeFirst()) else {
                    throw ControlError.invalid("`\(arg.name)` needs an integer")
                }
                args[arg.name] = .int(number)
            case .number:
                guard let number = Double(rest.removeFirst()) else {
                    throw ControlError.invalid("`\(arg.name)` needs a number")
                }
                args[arg.name] = .number(number)
            case .bool:
                let (value, problem) = ConfigOption.readBool(rest.removeFirst(), arg.name)
                if problem != nil { throw ControlError.invalid("`\(arg.name)` needs true or false") }
                args[arg.name] = .bool(value)
            default:
                args[arg.name] = .string(rest.removeFirst())
            }
        }
        if let extra = rest.first { throw ControlError.invalid("`\(command.name)` has no argument for `\(extra)`") }
        return args
    }

    static func render(_ result: JSON, compact: Bool) -> String {
        if compact { return result.text }
        switch result {
        case .null: return ""
        case .string(let text): return text
        default: return String(bytes: result.encoded(pretty: true), encoding: .utf8) ?? ""
        }
    }

    static func help(_ topic: String?) -> String {
        if let topic, let command = CommandRegistry.command(named: topic) {
            let usage = command.args.map { $0.required ? "<\($0.name)>" : "[\($0.name)]" }.joined(separator: " ")
            var lines = ["catwm \(command.name) \(usage)".trimmingCharacters(in: .whitespaces), "", command.summary]
            for arg in command.args {
                var line = "  \(arg.name): \(arg.summary)"
                if case .choice(let choices) = arg.kind { line += " (\(choices.joined(separator: ", ")))" }
                lines.append(line)
            }
            return lines.joined(separator: "\n")
        }
        var lines = ["Usage: catwm <command> [arguments] [--json]", "       catwm events [event ...]", ""]
        let commands = CommandRegistry.published
        let width = (commands.map(\.name.count).max() ?? 0) + 2
        var groups: [String] = []
        for command in commands where !groups.contains(command.group) { groups.append(command.group) }
        for group in groups {
            lines.append("\(group):")
            for command in commands where command.group == group {
                let name = command.name.padding(toLength: width, withPad: " ", startingAt: 0)
                lines.append("  \(name)\(command.summary)")
            }
            lines.append("")
        }
        lines.append("Events: \(EventBus.allNames.joined(separator: ", "))")
        lines.append("Use `--` before arguments that should be passed literally, including `--json`.")
        lines.append("Run `catwm help <command>` for the arguments of a command.")
        return lines.joined(separator: "\n")
    }

    private static func stream(_ names: [String]) -> Never {
        let connection = connect()
        let response = connection.call("subscribe", ["events": .array(names.map(JSON.string))])
        guard response["ok"]?.isTrue == true else {
            fail(response["error"]?["message"]?.string ?? "CatWM did not answer", code: 1)
        }
        connection.setTimeout(seconds: 0)
        while let line = connection.readLine() { print(String(bytes: line, encoding: .utf8) ?? ""); fflush(stdout) }
        exit(0)
    }

    private static func connect() -> Client {
        guard let client = Client(path: ControlServer.socketPath) else {
            fail("CatWM is not running. It listens on \(ControlServer.socketPath)", code: 1)
        }
        return client
    }

    private static func finish(_ text: String, code: Int32) -> Never {
        if !text.isEmpty { print(text) }
        exit(code)
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data("catwm: \(message)\n".utf8))
        exit(code)
    }

    final class Client {
        private let descriptor: Int32
        private var buffer = Data()
        private var nextID = 1

        func setTimeout(seconds: Int) {
            var value = timeval(tv_sec: seconds, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        }

        init?(path: String) {
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
            descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            var quiet: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
            let status = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard status == 0 else { Darwin.close(descriptor); return nil }
            setTimeout(seconds: 10)
            _ = readLine()
        }

        deinit { Darwin.close(descriptor) }

        func call(_ command: String, _ args: [String: JSON]) -> JSON {
            let id = nextID
            nextID += 1
            let request = JSON.object(["id": .int(id), "command": .string(command), "args": .object(args)])
            let data = request.encoded() + Data("\n".utf8)
            let sent = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            guard sent == data.count else { return ["ok": false, "error": ["message": "Could not send the command"]] }
            while let line = readLine() {
                if let reply = JSON.parse(line), reply["id"]?.int == id { return reply }
            }
            return ["ok": false, "error": ["message": "CatWM did not answer"]]
        }

        func readLine() -> Data? {
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer = Data(buffer[buffer.index(after: newline)...])
                    return line
                }
                var chunk = [UInt8](repeating: 0, count: 64 * 1024)
                let count = read(descriptor, &chunk, chunk.count)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return nil }
                buffer.append(contentsOf: chunk[0..<count])
            }
        }
    }
}
