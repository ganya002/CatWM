import AppKit
import CatWMKit

// A minimal host: it links CatWMKit, tiles the windows of the given pids and stops on SIGTERM.
// Usage: EmbedHost <pid>[,<pid>...]
@main
@MainActor
enum EmbedHost {
    static let config = """
        export default {
          features: {
            windows: { tiling: true },
            services: { socket: true },
          },
          gaps: { size: 8 },
        }
        """

    static func main() {
        let pids = (CommandLine.arguments.dropFirst().first ?? "").split(separator: ",").compactMap { Int32($0) }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let engine: CatWMEngine
        do {
            engine = try CatWMEngine(name: "embed-example")
            try engine.start(config: .text(config), scope: pids.isEmpty ? nil : CatWMEngine.Scope(pids: pids))
        } catch {
            FileHandle.standardError.write(Data("EmbedHost: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        report(engine.snapshot())
        Task {
            for await event in engine.events() { say("event \(event.name)") }
        }
        signal(SIGTERM, SIG_IGN)
        let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        stop.setEventHandler {
            Task { @MainActor in
                await engine.stop()
                report(engine.snapshot())
                say("stopped")
                exit(0)
            }
        }
        stop.resume()
        app.run()
    }

    static func report(_ snapshot: CatWMEngine.Snapshot) {
        let line: JSON = [
            "running": .bool(snapshot.isRunning), "tiling": .bool(snapshot.isTiling),
            "features": .array(snapshot.features.map(JSON.string)),
            "permissions": .object(snapshot.permissions.mapValues(JSON.bool)),
            "windows": .int(snapshot.windows.array?.count ?? 0)
        ]
        let data = (try? JSONEncoder().encode(line)) ?? Data()
        say(String(decoding: data, as: UTF8.self))
    }

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
