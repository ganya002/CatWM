@preconcurrency import Foundation
import JavaScriptCore
import os

package final class ConfigEngine {
    package static let timeLimit = 1.0

    package struct Run {
        package var value: JSON?
        package var files: [URL] = []
        package var failures: [ConfigDiagnostic] = []
        package var isNew = false
        package var isStuck = false
        package var milliseconds = 0.0
    }

    package struct WindowSnapshot: Sendable {
        package var title: String
        package var app: String
        package var pid: Int
        package var frame: CGRect

        package init(title: String, app: String, pid: Int, frame: CGRect) {
            self.title = title
            self.app = app
            self.pid = pid
            self.frame = frame
        }
    }

    package struct FunctionRun: Sendable {
        package var actions: [RuleAction] = []
        package var failure: ConfigDiagnostic?
    }

    package let entry: URL
    private let baseline: Config
    private let isLegacy: Bool
    private let check: (JSON) -> [ConfigDiagnostic]
    private let thread = RunLoopThread(name: "CatWM config")
    private var context: JSContext?
    private var value: JSON?
    private var files: [URL] = []
    private var hasCollected = false

    package init(entry: URL, baseline: Config = Config(), legacy: Bool = false,
                 check: @escaping (JSON) -> [ConfigDiagnostic] = { _ in [] }) {
        self.entry = entry
        self.baseline = baseline
        isLegacy = legacy
        self.check = check
    }

    deinit {
        let context = context
        thread.perform { _ = context }
        thread.stop()
    }

    package func run() -> Run { run(timeout: .infinity) ?? Run() }

    package func run(timeout: TimeInterval) -> Run? {
        final class Box {
            package let lock = NSLock()
            package var run: Run?
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        thread.perform {
            let run = self.evaluate()
            box.lock.withLock { box.run = run }
            done.signal()
        }
        let deadline: DispatchTime = timeout.isFinite ? .now() + timeout : .distantFuture
        guard done.wait(timeout: deadline) == .success else { return nil }
        return box.lock.withLock { box.run }
    }

    package func run(then finish: @escaping (Run) -> Void) {
        thread.perform { finish(self.evaluate()) }
    }

    package func call(function: Int, window: WindowSnapshot, then finish: @escaping (FunctionRun) -> Void) {
        thread.perform { finish(self.invoke(function, window)) }
    }

    private func evaluate() -> Run {
        let start = DispatchTime.now().uptimeNanoseconds
        var run = evaluateRegistry()
        run.milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return run
    }

    private func evaluateRegistry() -> Run {
        guard let context = context ?? makeContext() else {
            return Run(value: value, files: files,
                       failures: [ConfigDiagnostic(phase: .read, message: "CatWM can't start its TypeScript engine")])
        }
        self.context = context
        guard let registry = context.objectForKeyedSubscript("catwmRegistry") else { return Run(value: value) }
        let start = DispatchTime.now().uptimeNanoseconds
        let output = registry.invokeMethod("run", withArguments: [entry.path, isLegacy])?.toString() ?? ""
        let late = registry.invokeMethod("late", withArguments: [])?.toString() ?? "[]"
        collectGarbage(context)
        guard let result = JSON.parse(Data(output.utf8)) else {
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            let message = seconds >= Self.timeLimit
                ? "the config ran longer than \(Int(Self.timeLimit)) s, so CatWM stopped it. Look for an endless loop"
                : "the config run failed"
            return Run(value: value, files: files,
                       failures: [ConfigDiagnostic(file: entry.path, phase: .evaluate, message: message)])
        }
        let tried = (result["files"]?.array ?? []).compactMap(\.string).map { URL(fileURLWithPath: $0) }
        var failures = result["error"].map {
            [ConfigDiagnostic($0) ?? ConfigDiagnostic(phase: .evaluate, message: "\($0)")]
        } ?? []
        failures += (JSON.parse(Data(late.utf8))?.array ?? []).compactMap(ConfigDiagnostic.init)
        let next = result["value"] ?? .null
        if failures.isEmpty { failures = check(next) }
        guard failures.isEmpty else {
            return Run(value: value, files: files + tried.filter { !files.contains($0) }, failures: failures)
        }
        registry.invokeMethod("commit", withArguments: [])
        let isNew = next != value
        value = next
        files = tried
        return Run(value: next, files: files, isNew: isNew)
    }

    private func invoke(_ function: Int, _ window: WindowSnapshot) -> FunctionRun {
        guard let registry = context?.objectForKeyedSubscript("catwmRegistry") else {
            return FunctionRun(failure: ConfigDiagnostic(file: entry.path, phase: .evaluate,
                                                         message: "the config isn't loaded"))
        }
        let frame = window.frame
        let snapshot: [String: Any] = [
            "title": window.title, "app": window.app, "pid": window.pid,
            "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        ]
        let start = DispatchTime.now().uptimeNanoseconds
        let output = registry.invokeMethod("call", withArguments: [function, snapshot])?.toString() ?? ""
        guard let result = JSON.parse(Data(output.utf8)) else {
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            let message = seconds >= Self.timeLimit
                ? "the key's function ran longer than \(Int(Self.timeLimit)) s, so CatWM stopped it. "
                    + "Look for an endless loop"
                : "the key's function failed"
            return FunctionRun(failure: ConfigDiagnostic(file: entry.path, phase: .evaluate, message: message))
        }
        if let error = result["error"] {
            return FunctionRun(failure: ConfigDiagnostic(error)
                ?? ConfigDiagnostic(file: entry.path, phase: .evaluate, message: "\(error)"))
        }
        let actions = (result["actions"]?.array ?? []).compactMap { action -> RuleAction? in
            if let name = action.string { return RuleAction(dispatcher: name, arg: "") }
            guard let parts = action.array, let name = parts.first?.string else { return nil }
            return RuleAction(dispatcher: name, arg: parts.dropFirst().compactMap(\.string).joined(separator: ", "))
        }
        return FunctionRun(actions: actions)
    }

    private var setup: String {
        let styles = MotionStyle.all.map { JSON.object(["id": .string($0.id), "fields": .object($0.fields)]) }
        let value = JSON.object([
            "defaults": ConfigScript.defaults(for: baseline), "styles": .array(styles),
            "renamed": .object(ConfigScript.renamed.mapValues(JSON.string))
        ])
        return (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func collectGarbage(_ context: JSContext) {
        typealias CollectNow = @convention(c) (JSContextRef?) -> Void
        if !hasCollected, let collectNow: CollectNow = symbol("JSSynchronousGarbageCollectForDebugging") {
            hasCollected = true
            collectNow(context.jsGlobalContextRef)
        } else {
            JSGarbageCollect(context.jsGlobalContextRef)
        }
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
        context.evaluateScript(ConfigCatwm.source, withSourceURL: URL(fileURLWithPath: "catwm-module.js"))
        context.evaluateScript(ConfigRuntime.source, withSourceURL: URL(fileURLWithPath: "catwm-registry.js"))
        context.objectForKeyedSubscript("catwmModule")?.invokeMethod("install", withArguments: [setup])
        if let exception = context.exception {
            Log.info("config: the TypeScript engine did not start: \(exception)")
            return nil
        }
        return context
    }

    package static func useOneGCMarkerThread() {
        setenv("JSC_numberOfGCMarkers", "1", 0)
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
    private struct State {
        var loop: CFRunLoop?
        var running = true
    }

    private let runLoop: CFRunLoop
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init(name: String) {
        let state = state
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            state.withLock { $0.loop = CFRunLoopGetCurrent() }
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            while state.withLock({ $0.running }) { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
        guard let loop = state.withLock({ $0.loop }) else { fatalError("the config thread has no run loop") }
        runLoop = loop
    }

    package func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    package func stop() {
        let state = state
        perform { state.withLock { $0.running = false } }
    }
}
