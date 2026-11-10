import Foundation
import Testing

@Test func checkStylePasses() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let pipe = Pipe()
    let process = Process()
    process.executableURL = root.appendingPathComponent("Tools/check-style.sh")
    process.currentDirectoryURL = root
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(process.terminationStatus == 0, "\(output)")
}

private func styleFailures(path: String, source: String) throws -> [String] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let script = """
    import sys
    import importlib.util
    from importlib.machinery import SourceFileLoader
    loader = SourceFileLoader("style", sys.argv[1])
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader("style", loader))
    loader.exec_module(module)
    for failure in module.line_failures(sys.argv[2], sys.argv[3]):
        print(failure[2])
    """
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let checker = root.appendingPathComponent("Tools/check-style.sh").path
    process.arguments = ["python3", "-c", script, checker, path, source]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").map(String.init)
}

private let uiPath = "Sources/CatWM/UI/Example.swift"

@Test(arguments: [
    "NSAnimationContext.runAnimationGroup({ _ in }, completionHandler: nil)",
    "view.animator().alphaValue = 0",
    "let a = CABasicAnimation(keyPath: \"opacity\")",
    "let a = CASpringAnimation(keyPath: \"position\")",
    "let a = CAKeyframeAnimation(keyPath: \"position\")",
    "let a = CAAnimationGroup()",
    "let a = CATransition()"
])
func styleRejectsAppKitAnimation(line: String) throws {
    #expect(try styleFailures(path: uiPath, source: line).contains { $0.contains("AppKit animation outside Motion") })
    #expect(try styleFailures(path: "Sources/CatWM/Motion/Kit/Example.swift", source: line).isEmpty)
}

@Test func styleRejectsDisplayLinkOutsideMotion() throws {
    let line = "let link = view.displayLink(target: self, selector: #selector(step))"
    #expect(try styleFailures(path: uiPath, source: line).contains { $0.contains("display link") })
    let failures = try styleFailures(path: uiPath, source: "var link: CADisplayLink?")
    #expect(failures.contains { $0.contains("display link") })
    #expect(try styleFailures(path: "Sources/CatWMKit/Motion/Desktop/Example.swift", source: line).isEmpty)
    #expect(try styleFailures(path: "Sources/CatWM/App/Perf/FrameRun.swift", source: line).isEmpty)
}

@Test(arguments: [
    "let a = CAPropertyAnimation(keyPath: \"opacity\")",
    "withAnimation(reduce ? Motion.fade : .default) { x = 1 }",
    "let a = Animation.default",
    "withAnimation(foo) { apply(reduce ? Motion.fade : Motion.easeOut) }",
    ".animation(bar, value: x)"
])
func styleRejectsAnimationBypasses(line: String) throws {
    #expect(try !styleFailures(path: uiPath, source: line).isEmpty)
}

@Test func styleRejectsFastTimers() throws {
    for line in [
        "let t = Timer(timeInterval: 1 / 60, repeats: true) { _ in }",
        "let t = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in }",
        "Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in }",
        "let t = Timer("
    ] {
        #expect(try styleFailures(path: uiPath, source: line).contains { $0.contains("frame timer") }, "\(line)")
    }
    for line in [
        "let t = Timer(timeInterval: 0.25, repeats: true) { _ in }",
        "Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }",
        "let t = Timer(timeInterval: 1 / 4, repeats: true) { _ in }"
    ] {
        #expect(try styleFailures(path: uiPath, source: line).isEmpty, "\(line)")
    }
    let timer = "let t = Timer(timeInterval: 1 / 120, repeats: true) { _ in }"
    #expect(try styleFailures(path: "Sources/CatWM/Motion/Kit/Example.swift", source: timer).isEmpty)
}

@Test(arguments: [
    "let a = Animation.easeOut(duration: 0.2)",
    "withAnimation(.easeIn(duration: 0.2)) { x = 1 }",
    ".animation(.easeInOut(duration: 1), value: x)",
    "let a = Animation.linear(duration: 2)",
    ".animation(.spring(response: 0.3), value: x)",
    "withAnimation(.snappy) { x = 1 }",
    "withAnimation(.bouncy) { x = 1 }",
    "withAnimation(.smooth) { x = 1 }",
    "let a = Animation.timingCurve(0, 0, 1, 1)",
    "let a = Animation.interpolatingSpring(stiffness: 1, damping: 1)",
    "let a = Animation(CustomCurve())",
    "struct Bounce: CustomAnimation {"
])
func styleRejectsRawSwiftUIAnimation(line: String) throws {
    #expect(try styleFailures(path: uiPath, source: line).contains { $0.contains("raw SwiftUI animation") }, "\(line)")
    let keys = "Sources/CatWM/Keys/Keyboard/Example.swift"
    #expect(try styleFailures(path: keys, source: line).contains { $0.contains("raw SwiftUI animation") })
    #expect(try styleFailures(path: "Sources/CatWM/Motion/Kit/Motion.swift", source: line).isEmpty)
}

@Test func styleRequiresMotionTokenForAnimationArguments() throws {
    for line in [
        "withAnimation(PanelMotion.current.animation(in: true)) { x = 1 }",
        "withAnimation { x = 1 }",
        ".animation(style.animation(in: shown), value: shown)"
    ] {
        #expect(try styleFailures(path: uiPath, source: line).contains { $0.contains("Motion.* token") }, "\(line)")
    }
    for line in [
        "withAnimation(Motion.fade) { x = 1 }",
        "withAnimation(reduce ? Motion.fade : Motion.spring) { x = 1 }",
        "withAnimation(!reduce ? Motion.fade : Motion.easeOut) { x = 1 }",
        "withAnimation(reduce && enabled ? Motion.fade : Motion.easeOut) { x = 1 }",
        ".animation(Motion.easeOut, value: x)",
        ".animation(nil, value: x)",
        "withAnimation(nil) { x = 1 }"
    ] {
        #expect(try styleFailures(path: uiPath, source: line).isEmpty, "\(line)")
    }
}

@Test func styleOkCannotSilenceAnimationRules() throws {
    let line = "view.animator().alphaValue = 0 // style-ok: one-off fade for the panel"
    let failures = try styleFailures(path: uiPath, source: line)
    #expect(failures.contains { $0.contains("AppKit animation outside Motion") })
    #expect(failures.contains { $0.contains("style-ok cannot silence an animation rule") })
    let panel = "let panel = NSPanel(contentRect: .zero) // style-ok: needs a raw panel here"
    let other = try styleFailures(path: uiPath, source: panel)
    #expect(!other.contains { $0.contains("style-ok") })
}

@Test func styleAppliesTilingRulesToMotionEngine() throws {
    let wait = "DispatchQueue.main.async" + "After(deadline: .now() + 1) { }"
    let hud = "HUD.shared.show()"
    for folder in ["Engine", "Windows", "Desktop"] {
        let path = "Sources/CatWMKit/Motion/\(folder)/Example.swift"
        #expect(try styleFailures(path: path, source: wait).contains { $0.contains("timer wait") }, "\(folder)")
        #expect(try styleFailures(path: path, source: hud).contains { $0.contains("UI in Tiling") }, "\(folder)")
    }
    #expect(try styleFailures(path: "Sources/CatWM/Motion/Kit/Example.swift", source: wait).isEmpty)
    let excused = wait + " // style-ok: no event exists for this"
    #expect(try styleFailures(path: "Sources/CatWMKit/Motion/Windows/Example.swift", source: excused).isEmpty)
}
