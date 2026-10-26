import AppKit

let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), index + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Previews.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    exit(0)
}
let controller = MainActor.assumeIsolated { AppController() }
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
