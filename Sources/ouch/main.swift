import AppKit

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

let cliArgs = Array(CommandLine.arguments.dropFirst())
if let cmd = cliArgs.first, ["dispatch", "dump", "reload", "poststyle", "grabtest", "modefx", "panelfx", "intro", "introlab"].contains(cmd) {
    DistributedNotificationCenter.default().postNotificationName(ipcNotification, object: cliArgs.joined(separator: " "),
                                                                 userInfo: nil, deliverImmediately: true)
    if cmd == "dump" { print("State written to \(Log.url.path)") }
    exit(0)
}

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        WindowManager.shared.isStarted = false
        WindowManager.shared.restoreHiddenWindows {
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
