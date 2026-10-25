import AppKit

if CommandLine.arguments.dropFirst().first == "--native-desktop-guard" {
    DesktopGuard.run()
}

if CommandLine.arguments.dropFirst().first == "--write-config-docs" {
    try AgentConfigDocs.write(in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "practice" {
    let args = Array(CommandLine.arguments.dropFirst(2))
    let titles = args.count > 1 ? args[1].split(separator: ",").map(String.init) : []
    PracticeDesk.run(parent: pid_t(args.first ?? "") ?? getppid(), titles: titles)
}

if CommandLine.arguments.dropFirst().first == "docs" {
    if let dir = Bundle.main.resourceURL?.appendingPathComponent("AgentDocs"),
       FileManager.default.fileExists(atPath: dir.path) {
        print(dir.path)
        exit(0)
    }
    FileHandle.standardError.write(Data("No bundled docs found\n".utf8))
    exit(1)
}

if CommandLine.arguments.dropFirst().first == "--write-schema" {
    try ControlSchema.write(in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    exit(0)
}

Migrations.run()

switch LaunchArguments.decide(Array(CommandLine.arguments.dropFirst())) {
case .start: break
case .cli(let words): ControlCLI.run(words)
case .usage(let message):
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

signal(SIGPIPE, SIG_IGN)
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        WindowManager.shared.isStarted = false
        ControlServer.shared.stop()
        WindowManager.shared.restoreHiddenWindows {
            CapsLockChord.shared.restore()
            CrashWatch.cleanExit()
            exit(0)
        }
    }
    source.resume()
    signalSources.append(source)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
