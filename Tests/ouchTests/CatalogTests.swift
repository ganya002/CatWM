import AppKit
import Foundation
import SwiftUI
import Testing

@testable import ouch

private func preservesOriginalOrder(_ actual: [String], _ original: [String]) -> Bool {
    actual.filter { original.contains($0) } == original
}

private let originalPointerIDs = ["float", "zoom", "native", "main", "layout", "display", "workspace", "dim", "blur", "minimize", "close"]

private var catalogRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

@Test func generatedAgentConfigMatchesTheCatalog() throws {
    let directory = catalogRoot.appendingPathComponent("Resources/AgentDocs")
    let template = try String(contentsOf: directory.appendingPathComponent("config.template.md"), encoding: .utf8)
    let actual = try String(contentsOf: directory.appendingPathComponent("config.md"), encoding: .utf8)
    #expect(actual == AgentConfigDocs.render(template), "Run swift run ouch --write-config-docs")
}

@Test func everySettingHasOneRendererPlacement() throws {
    let directory = catalogRoot.appendingPathComponent("Sources/ouch/Settings/Panes")
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let expression = try NSRegularExpression(pattern: #"OptionRows\s*\(\s*pane:\s*\.(\w+)\s*,\s*section:\s*"([^"]+)"(?:\s*,\s*advanced:\s*(true))?"#)
    var placed: [String] = []
    for file in files where file.pathExtension == "swift" {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let paneName = String(source[Range(match.range(at: 1), in: source)!])
            let section = String(source[Range(match.range(at: 2), in: source)!])
            let pane = try #require(Pane.allCases.first { $0.rawValue.lowercased() == paneName })
            placed += OptionRows.options(pane: pane, section: section, advanced: match.range(at: 3).location != NSNotFound).map(\.key)
        }
    }
    for pane in Pane.allCases {
        for advanced in [false, true] {
            for section in OptionRows.additionalSections(pane: pane, advanced: advanced) {
                placed += OptionRows.options(pane: pane, section: section, advanced: advanced).map(\.key)
            }
        }
    }
    let declared = Options.all.filter { $0.setting != nil }.map(\.key)
    #expect(placed.sorted() == declared.sorted())
    #expect(Set(placed).count == placed.count)
}

@Test func settingsKeepTheirRowOrder() {
    #expect(
        preservesOriginalOrder(
            OptionRows.options(pane: .windows, section: "Focus", advanced: false).map { $0.ui.id },
            [
                "windows.ffm", "windows.ffmModeOnly", "windows.mff", "windows.dimOthers", "windows.dimStrength", "windows.blurOthers",
                "windows.blurRadius",
            ]))
    #expect(
        preservesOriginalOrder(
            OptionRows.options(pane: .windows, section: "Workspaces", advanced: false).map { $0.ui.id },
            [
                "windows.workspaces", "windows.sortStrategy", "windows.sortNudge",
            ]))
    #expect(
        preservesOriginalOrder(
            OptionRows.options(pane: .layout, section: "Gaps", advanced: false).map { $0.ui.id },
            [
                "layout.gaps", "layout.gapSize", "layout.smartGaps",
            ]))
}

@Test func pointerCatalogKeepsItsOrderAndUniqueIdentities() {
    #expect(
        preservesOriginalOrder(
            PointerActions.all.map(\.id),
            ["float", "zoom", "native", "main", "layout", "display", "workspace", "dim", "blur", "minimize", "close"]))
    #expect(Set(PointerActions.all.map(\.id)).count == PointerActions.all.count)
    #expect(Set(PointerActions.all.map(\.menuID)).count == PointerActions.all.count)
    for spec in PointerActions.all {
        #expect(Actions.dispatchers.contains(spec.dispatcher))
        if !spec.nextWorkspace {
            #expect(Actions.match(BindRow(mods: "", key: "", dispatcher: spec.dispatcher, args: spec.args))?.id == spec.action.id)
        }
        if let hint = spec.hint { #expect(KeyHint.label(dispatcher: spec.dispatcher, arg: spec.args) == hint) }
    }
}

@Test func pointerAvailabilityKeepsWindowRules() {
    let floating = CursorShortcutSpec.Context(
        floating: true, tiled: false, zoomed: false, nativeFullscreen: false,
        canMakeMain: false, multipleLayouts: false, multipleDisplays: false, virtualWorkspace: false)
    #expect(
        PointerActions.all.filter { $0.available(floating) && originalPointerIDs.contains($0.id) }.map(\.id) == [
            "float", "native", "dim", "blur", "minimize", "close",
        ])
    let tiled = CursorShortcutSpec.Context(
        floating: false, tiled: true, zoomed: true, nativeFullscreen: false,
        canMakeMain: true, multipleLayouts: true, multipleDisplays: true, virtualWorkspace: true)
    #expect(
        PointerActions.all.filter {
            ["float", "zoom", "native", "main", "layout", "display", "workspace", "dim", "blur", "minimize", "close"].contains($0.id)
        }.allSatisfy { $0.available(tiled) })
    #expect(PointerActions.all.first { $0.id == "zoom" }?.selected(tiled) == true)
}

@Test func dispatcherRegistryContainsEveryActionAndNoDuplicates() {
    #expect(Set(Actions.dispatchers).count == Actions.dispatchers.count)
    #expect(Actions.all.allSatisfy { Actions.dispatchers.contains($0.dispatcher) })
    for feature in FocusDim.features {
        #expect(Options.all.contains { $0.key == feature.options.first?.key })
        #expect(PointerActions.all.contains { $0.id == feature.pointer.id })
    }
}

#if DEBUG
    @Test func galleryDiscoversEachExampleOnceInOrder() {
        let ids = GalleryExamples.all.map(\.id)
        #expect(ids == ids.sorted())
        #expect((0...14).allSatisfy { ids.contains($0) })
        #expect(Set(ids).count == ids.count)
    }
#endif

@Test func catalogLintRejectsTheFormerWorkflow() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [catalogRoot.appendingPathComponent("Tools/test-catalog-rules.py").path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(process.terminationStatus == 0, "\(output)")
}

@Test func shortcutActionMenuKeepsItsOriginalWindowOrder() {
    let original = ["togglefloating ", "fullscreen ", "nativefullscreen ", "killactive ", "minimize ", "sort ", "sort-undo "]
    #expect(preservesOriginalOrder(Actions.all.filter { $0.category == .window }.map(\.id), original))
}

@Test func customSearchEntriesUseTheirDeclaredAnchor() throws {
    let root = catalogRoot.appendingPathComponent("Sources/ouch/Settings")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var source = ""
    for case let file as URL in files where file.pathExtension == "swift" {
        source += try String(contentsOf: file, encoding: .utf8)
    }
    let declaration = try NSRegularExpression(pattern: #"static let (search\w+) = SettingEntry\(id: "([^"]+)""#)
    let matches = declaration.matches(in: source, range: NSRange(source.startIndex..., in: source))
    #expect(matches.count == CustomSettingsIndex.all.count)
    for match in matches {
        let name = String(source[Range(match.range(at: 1), in: source)!])
        let id = String(source[Range(match.range(at: 2), in: source)!])
        #expect(source.contains(".\(name).id, ui)"), "No row uses \(id)")
        #expect(CustomSettingsIndex.all.contains { $0.id == id })
    }
}

#if DEBUG
    @MainActor
    @Test func rendersSettingsCatalog() throws {
        guard let directory = ProcessInfo.processInfo.environment["OUCH_SETTINGS_PNG"] else { return }
        let doc = ConfigDocument(text: defaultText)
        let ui = SettingsUI(doc: doc)
        ui.advancedOpen = Set(Pane.allCases)
        let views: [(String, AnyView)] = [
            ("windows", AnyView(WindowsPane(doc: doc, ui: ui))),
            ("layout", AnyView(LayoutPane(doc: doc, ui: ui))),
            ("motion", AnyView(MotionPane(doc: doc, ui: ui))),
            ("shortcuts", AnyView(ShortcutsPane(doc: doc, ui: ui))),
        ]
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, view) in views {
            let host = NSHostingView(
                rootView: VStack(alignment: .leading) {
                    view
                    Spacer(minLength: 0)
                }
                .padding(Theme.Space.page).background(Theme.bg))
            host.frame = NSRect(x: 0, y: 0, width: 660, height: 4000)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            #expect(png.count > 20_000)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
    }
#endif

@Test func directionCatalogKeepsActionAndHintNames() {
    #expect(Direction.allCases.map(\.rawValue) == ["l", "r", "u", "d"])
    #expect(Direction.allCases.map(\.title) == ["Left", "Right", "Up", "Down"])
    #expect(Direction.hintArrows == ["l": "←", "left": "←", "r": "→", "right": "→", "u": "↑", "up": "↑", "d": "↓", "down": "↓"])
    #expect(KeyHint.label(dispatcher: "movefocus", arg: "top") == "Focus")
}
