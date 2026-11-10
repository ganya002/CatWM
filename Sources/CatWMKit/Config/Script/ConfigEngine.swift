import Foundation
import JavaScriptCore

package final class ConfigEngine {
    package static let timeLimit = 1.0

    package enum Pass {
        case all
        case changed
    }

    package struct Run {
        package var value: JSON?
        package var ran: [String] = []
        package var files: [URL] = []
        package var failures: [ConfigDiagnostic] = []
        package var isNew = false
        package var isStuck = false
        package var milliseconds = 0.0
    }

    package let entry: URL
    private let check: (JSON) -> [ConfigDiagnostic]
    private let thread = RunLoopThread(name: "CatWM config")
    private var context: JSContext?
    private var value: JSON?
    private var files: [URL] = []

    package init(entry: URL, check: @escaping (JSON) -> [ConfigDiagnostic] = { _ in [] }) {
        self.entry = entry
        self.check = check
    }

    deinit {
        let context = context
        thread.perform { _ = context }
        thread.stop()
    }

    package func run(_ pass: Pass) -> Run { run(pass, timeout: .infinity) ?? Run() }

    package func run(_ pass: Pass, timeout: TimeInterval) -> Run? {
        final class Box {
            package let lock = NSLock()
            package var run: Run?
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        thread.perform {
            let run = self.evaluate(pass)
            box.lock.withLock { box.run = run }
            done.signal()
        }
        let deadline: DispatchTime = timeout.isFinite ? .now() + timeout : .distantFuture
        guard done.wait(timeout: deadline) == .success else { return nil }
        return box.lock.withLock { box.run }
    }

    package func run(_ pass: Pass, then finish: @escaping (Run) -> Void) {
        thread.perform { finish(self.evaluate(pass)) }
    }

    private func evaluate(_ pass: Pass) -> Run {
        let start = DispatchTime.now().uptimeNanoseconds
        var run = evaluateRegistry(pass)
        run.milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return run
    }

    private func evaluateRegistry(_ pass: Pass) -> Run {
        guard let context = context ?? makeContext() else {
            return Run(value: value, files: files,
                       failures: [ConfigDiagnostic(phase: .read, message: "CatWM can't start its TypeScript engine")])
        }
        self.context = context
        guard let registry = context.objectForKeyedSubscript("catwmRegistry") else { return Run(value: value) }
        var changed: Any = NSNull()
        if pass == .changed, value != nil {
            let paths = registry.invokeMethod("changed", withArguments: [])?.toArray() as? [String] ?? []
            if paths.isEmpty { return Run(value: value, files: files) }
            changed = paths
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let output = registry.invokeMethod("run", withArguments: [entry.path, changed])?.toString() ?? ""
        JSGarbageCollect(context.jsGlobalContextRef)
        guard let result = JSON.parse(Data(output.utf8)) else {
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            guard seconds >= Self.timeLimit else {
                let failure = ConfigDiagnostic(file: entry.path, phase: .evaluate, message: "the config run failed")
                return Run(value: value, files: files, failures: [failure])
            }
            registry.invokeMethod("rollback", withArguments: [])
            let message = "the config ran longer than \(Int(Self.timeLimit)) s, so CatWM stopped it. "
                + "Look for an endless loop"
            return Run(value: value, files: files,
                       failures: [ConfigDiagnostic(file: entry.path, phase: .evaluate, message: message)])
        }
        let ran = result["ran"]?.array?.compactMap(\.string) ?? []
        if let error = result["error"] {
            let tried = (result["files"]?.array ?? []).compactMap(\.string).map { URL(fileURLWithPath: $0) }
            return Run(value: value, ran: ran, files: files + tried.filter { !files.contains($0) },
                       failures: [ConfigDiagnostic(error) ?? ConfigDiagnostic(phase: .evaluate, message: "\(error)")])
        }
        let next = result["value"] ?? .null
        let problems = check(next)
        if !problems.isEmpty {
            registry.invokeMethod("rollback", withArguments: [])
            let tried = (result["files"]?.array ?? []).compactMap(\.string).map { URL(fileURLWithPath: $0) }
            return Run(value: value, ran: ran, files: files + tried.filter { !files.contains($0) }, failures: problems)
        }
        let isNew = next != value
        value = next
        files = (result["files"]?.array ?? []).compactMap(\.string).map { URL(fileURLWithPath: $0) }
        return Run(value: next, ran: ran, files: files, isNew: isNew)
    }

    private func makeContext() -> JSContext? {
        guard let context = JSContext() else { return nil }
        context.name = "CatWM config"
        typealias ShouldStop = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool
        typealias SetTimeLimit = @convention(c) (JSContextGroupRef?, Double, ShouldStop?,
                                                 UnsafeMutableRawPointer?) -> Void
        if let setTimeLimit: SetTimeLimit = symbol("JSContextGroupSetExecutionTimeLimit") {
            setTimeLimit(JSContextGetGroup(context.jsGlobalContextRef), Self.timeLimit, nil, nil)
        } else {
            Log.info("config: JSContextGroupSetExecutionTimeLimit is missing, so an endless loop can't be stopped")
        }
        let read: @convention(block) (String) -> JSValue = { path in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                return JSValue(undefinedIn: JSContext.current())
            }
            return JSValue(object: text, in: JSContext.current())
        }
        let resolve: @convention(block) (String, String) -> JSValue = { from, specifier in
            guard let path = Self.resolve(specifier, from: from) else {
                return JSValue(undefinedIn: JSContext.current())
            }
            return JSValue(object: path, in: JSContext.current())
        }
        let candidate: @convention(block) (String, String) -> JSValue = { from, specifier in
            let base = URL(fileURLWithPath: from).deletingLastPathComponent()
            let path = URL(fileURLWithPath: specifier, relativeTo: base).standardizedFileURL.path
            return JSValue(object: path, in: JSContext.current())
        }
        let compile: @convention(block) (String, String) -> JSValue? = { path, code in
            JSContext.current()?.evaluateScript("(function (exports, require, module) {" + code + "\n})",
                                                withSourceURL: URL(fileURLWithPath: path))
        }
        let host = JSValue(newObjectIn: context)
        host?.setValue(read, forProperty: "read")
        host?.setValue(resolve, forProperty: "resolve")
        host?.setValue(compile, forProperty: "compile")
        host?.setValue(candidate, forProperty: "candidate")
        context.globalObject.setValue(host, forProperty: "catwmHost")
        context.evaluateScript(Sucrase.source, withSourceURL: URL(fileURLWithPath: "sucrase.js"))
        context.evaluateScript(ConfigRuntime.source, withSourceURL: URL(fileURLWithPath: "catwm-registry.js"))
        if let exception = context.exception {
            Log.info("config: the TypeScript engine did not start: \(exception)")
            return nil
        }
        return context
    }

    package static func resolve(_ specifier: String, from importer: String) -> String? {
        guard specifier.hasPrefix("./") || specifier.hasPrefix("../") || specifier.hasPrefix("/") else { return nil }
        let base = URL(fileURLWithPath: importer).deletingLastPathComponent()
        let path = URL(fileURLWithPath: specifier, relativeTo: base).standardizedFileURL.path
        let stem = path.hasSuffix(".js") ? String(path.dropLast(3)) : path
        for candidate in [path, stem + ".ts", stem + "/index.ts"] where !candidate.hasSuffix(".d.ts") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }
}

private final class RunLoopThread {
    private final class State {
        package var loop: CFRunLoop?
        package var running = true
    }

    private let runLoop: CFRunLoop
    private let state = State()

    package init(name: String) {
        let state = state
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            state.loop = CFRunLoopGetCurrent()
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            while state.running { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
        guard let loop = state.loop else { fatalError("the config thread has no run loop") }
        runLoop = loop
    }

    package func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    package func stop() {
        let state = state
        perform { state.running = false }
    }
}
