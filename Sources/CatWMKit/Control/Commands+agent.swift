import AppKit

extension CommandRegistry {
    private static let windowArg = CommandArg(name: "window", kind: .int, summary: "Window ID from `agent.windows`")

    private static func windowID(_ call: Invocation) -> CGWindowID { CGWindowID(call.args["window"]?.int ?? 0) }

    private static func target(_ call: Invocation) throws -> (pid: pid_t, window: AXUIElement) {
        let display = try call.manager.agents.display(for: call.client)
        let id = windowID(call)
        guard let pid = display.windowIDs().first(where: { $0.id == id })?.pid,
              let window = AgentWindowIO.window(id, pid: pid) else {
            throw ControlError(code: "no_window", message: "Window \(id) is not on the agent display")
        }
        return (pid, window)
    }

    package static let agent: [Command] = [
        Command(name: "agent.open", group: "agent", summary: "Open a private display for test apps", result: .object([
            Field(name: "uuid", type: "string", summary: "Display ID"),
            Field(name: "frame", type: "rect", summary: "Display frame")
        ])) { call in
            let display = try call.manager.agents.open(for: call.client)
            return ["uuid": .string(display.uuid), "frame": .rect(display.bounds)]
        },
        .later(name: "agent.launch", group: "agent",
               summary: "Open an app on the agent display without focus. Fails if the app already runs",
               args: [.text("app", "Bundle ID")], result: .object([
                Field(name: "pid", type: "int", summary: "Process ID of the app")
               ])) { call in
            let display = try call.manager.agents.display(for: call.client)
            do {
                return ["pid": .int(Int(try await display.launch(call.text("app"))))]
            } catch AgentDisplay.LaunchError.notFound {
                throw ControlError(code: "app_not_found", message: "No app has the bundle ID `\(call.text("app"))`")
            } catch AgentDisplay.LaunchError.running {
                throw ControlError(code: "app_running",
                                   message: "`\(call.text("app"))` already runs. Quit it first, or pick another app")
            } catch {
                throw ControlError(code: "launch_failed", message: "`\(call.text("app"))` did not open")
            }
        },
        Command(name: "agent.windows", group: "agent", summary: "List the windows on the agent display",
                result: .list([
                    Field(name: "id", type: "int", summary: "Window ID"),
                    Field(name: "pid", type: "int", summary: "Process ID"),
                    Field(name: "app", type: "string?", summary: "Bundle ID"),
                    Field(name: "title", type: "string?", summary: "Window title"),
                    Field(name: "frame", type: "rect", summary: "Window frame")
                ])) { call in
            let display = try call.manager.agents.display(for: call.client)
            return .array(display.windowIDs().map { pid, id in
                let title = AgentWindowIO.window(id, pid: pid).flatMap(AgentWindowIO.title)
                return [
                    "id": .int(Int(id)), "pid": .int(Int(pid)),
                    "app": NSRunningApplication(processIdentifier: pid)?.bundleIdentifier.map(JSON.string) ?? .null,
                    "title": title.map(JSON.string) ?? .null, "frame": .rect(display.frame(of: id) ?? .zero)
                ]
            })
        },
        Command(name: "agent.type", group: "agent", summary: "Type text into a window without focusing it",
                args: [windowArg, .text("text", "Text to add after the current text")],
                result: .object([Field(name: "method", type: "string", summary: "`ax` or `events`")])) { call in
            let (pid, window) = try target(call)
            return ["method": .string(AgentWindowIO.type(call.text("text"), in: window, pid: pid))]
        },
        Command(name: "agent.key", group: "agent", summary: "Send a key to a window without focusing it",
                args: [windowArg, .text("keys", "Key, with modifiers: `return`, `cmd+a`, `cmd+shift+z`")]) { call in
            try AgentWindowIO.press(call.text("keys"), pid: target(call).pid)
            return .null
        },
        Command(name: "agent.press", group: "agent", summary: "Press a button of a window without focusing it",
                args: [windowArg, .text("button", "Button title, such as `New Document`")]) { call in
            let (_, window) = try target(call)
            guard AgentWindowIO.press(button: call.text("button"), in: window) else {
                throw ControlError(code: "no_button", message: "The window has no button `\(call.text("button"))`")
            }
            return .null
        },
        Command(name: "agent.text", group: "agent", summary: "Read the text of a window",
                args: [windowArg], result: .text) { call in
            let (pid, window) = try target(call)
            guard let text = AgentWindowIO.text(in: window, pid: pid) else {
                throw ControlError(code: "no_text", message: "The window has no text field")
            }
            return .string(text)
        },
        .later(name: "agent.screenshot", group: "agent", summary: "Save one frame of a window as a PNG file",
               args: [windowArg, .text("path", "Absolute path of the PNG file")], result: .text) { call in
            _ = try target(call)
            let path = call.text("path")
            guard path.hasPrefix("/") else { throw ControlError.invalid("`path` must be absolute") }
            try await AgentWindowIO.capture(windowID(call), to: URL(fileURLWithPath: path))
            return .string(path)
        },
        .later(name: "agent.close", group: "agent",
               summary: "Quit the apps that opened on the agent display and close it") { call in
            if let client = call.client, let display = call.manager.agents.take(client) { await display.quit() }
            return .null
        }
    ]
}
