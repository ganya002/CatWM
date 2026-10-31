import AppKit
@testable import CatWM
import Testing

@Suite struct WorkspaceTemplateTests {
    func template() -> WorkspaceTemplate {
        WorkspaceTemplate(name: "Writing", tilingEnabled: true, displays: [
            .init(id: "external", name: "Desk", frame: CGRect(x: 0, y: 0, width: 2000, height: 1200),
                  visible: CGRect(x: 0, y: 24, width: 2000, height: 1176), isMain: true,
                  layout: "tall", ratio: 0.65, mainCount: 2),
            .init(id: "builtin", name: "Laptop", frame: CGRect(x: -1000, y: 0, width: 1000, height: 800),
                  visible: CGRect(x: -1000, y: 24, width: 1000, height: 776), isMain: false,
                  layout: "floating", ratio: 0.5, mainCount: 1)
        ], windows: [
            .init(bundleID: "com.example.editor", appName: "Editor", title: "Draft", document: "file:///tmp/draft.txt",
                  display: "external", frame: CGRect(x: 0, y: 24, width: 1300, height: 1176), floating: false,
                  minimized: true, fullscreen: false, zoomed: true, focused: false, windowID: 42,
                  launchDate: Date(timeIntervalSince1970: 100))
        ])
    }

    @Test func roundTripKeepsLayoutAndWindowState() throws {
        var original = template()
        original.screenshot = Data([1, 2, 3, 4])
        let decoded = try JSONDecoder().decode(WorkspaceTemplate.self, from: JSONEncoder().encode(original))
        #expect(decoded.id == original.id)
        #expect(decoded.displays[0].ratio == 0.65)
        #expect(decoded.displays[0].mainCount == 2)
        #expect(decoded.displays[1].frame.minX == -1000)
        #expect(decoded.windows[0].document == "file:///tmp/draft.txt")
        #expect(decoded.windows[0].minimized)
        #expect(decoded.windows[0].zoomed)
        #expect(!decoded.windows[0].floating)
        #expect(decoded.screenshot == original.screenshot)
    }

    @Test func templatesWithoutScreenshotsStillLoad() throws {
        let data = try JSONEncoder().encode(template())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["screenshot"] == nil)
        let decoded = try JSONDecoder().decode(WorkspaceTemplate.self, from: data)
        #expect(decoded.screenshot == nil)
        #expect(decoded.name == "Writing")
    }

    @Test func textEntryPassesKeysThroughWindowMode() throws {
        let hotkeys = Hotkeys()
        hotkeys.submap = "window"
        hotkeys.textInputActive = true
        for code: UInt16 in [1, 18, 36, 53, 123, 124] {
            let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
            event.flags = []
            guard case .pass = hotkeys.match(event) else {
                Issue.record("Template naming intercepted key \(code)")
                continue
            }
        }
        hotkeys.textInputActive = false
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 1, keyDown: true))
        event.flags = []
        guard case .swallow = hotkeys.match(event) else {
            Issue.record("Window mode did not resume after naming")
            return
        }
    }

    @Test @MainActor func textEntryPassesRawCapsLockThroughWindowMode() {
        let hotkeys = Hotkeys()
        let bind = KeyBinding(keyCode: CapsLockChord.keyCode, mods: .maskCommand,
                              dispatcher: "submap", arg: "reset", submap: "window")
        hotkeys.tables = ["window": [Hotkeys.key(bind.keyCode, bind.mods): bind]]
        hotkeys.submap = "window"
        hotkeys.textInputActive = true

        #expect(!hotkeys.fireCapsLock(.maskCommand))
        #expect(hotkeys.submap == "window")

        hotkeys.textInputActive = false
        #expect(hotkeys.fireCapsLock(.maskCommand))
        #expect(hotkeys.submap.isEmpty)
    }

    @Test(arguments: [false, true]) @MainActor
    func textEntryPassesScrollThroughWindowMode(continuous: Bool) throws {
        let hotkeys = Hotkeys()
        let bind = KeyBinding(keyCode: SpecialKey.mouseDown, mods: [],
                              dispatcher: "submap", arg: "reset", submap: "window")
        hotkeys.tables = ["window": [Hotkeys.key(bind.keyCode, bind.mods): bind]]
        hotkeys.submap = "window"
        hotkeys.textInputActive = true
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line,
                                        wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0))
        event.flags = []

        #expect(!hotkeys.handlePointer(.scrollWheel, event))
        #expect(hotkeys.submap == "window")

        hotkeys.textInputActive = false
        #expect(hotkeys.handlePointer(.scrollWheel, event))
        #expect(hotkeys.submap.isEmpty)
    }

    @Test func exactDisplaysKeepTheirAssignmentsAfterReordering() {
        let mapping = template().displayMap(available: [("builtin", true), ("external", false)])
        #expect(mapping["external"] == "external")
        #expect(mapping["builtin"] == "builtin")
    }

    @Test func missingDisplaysUseAvailableScreenWithoutLosingWindows() {
        let mapping = template().displayMap(available: [("replacement", true)])
        #expect(mapping.count == 2)
        #expect(Set(mapping.values) == ["replacement"])
        #expect(template().displayMap(available: []).isEmpty)
    }

    @Test func replacementMainDisplayGetsSavedMainLayout() {
        let mapping = template().displayMap(available: [("left", false), ("main", true)])
        #expect(mapping["external"] == "main")
        #expect(mapping["builtin"] == "left")
    }

    @Test func framesScaleAcrossScreenSizesAndOrigins() {
        let frame = WorkspaceTemplate.restoredFrame(CGRect(x: -900, y: 100, width: 500, height: 400),
                                                    from: CGRect(x: -1000, y: 0, width: 1000, height: 800),
                                                    to: CGRect(x: 0, y: 24, width: 2000, height: 1600))
        #expect(frame == CGRect(x: 200, y: 224, width: 1000, height: 800))
    }

    @Test func oversizedAndOffscreenFramesStayInsideDisplay() {
        let bounds = CGRect(x: 0, y: 24, width: 800, height: 600)
        let frame = WorkspaceTemplate.restoredFrame(CGRect(x: -200, y: 800, width: 1800, height: 1200),
                                                    from: CGRect(x: 0, y: 0, width: 1000, height: 800), to: bounds)
        #expect(bounds.contains(frame))
        #expect(frame == bounds)
    }

    @Test func documentMatchRejectsUnrelatedWindowsEvenWithReusedID() {
        let saved = template().windows[0]
        #expect(WindowMatch.score(saved, title: "Other", document: "file:///tmp/other.txt", windowID: 42,
                                         launchDate: saved.launchDate) == nil)
        #expect(WindowMatch.score(saved, title: "Draft", document: nil, windowID: 12, launchDate: nil) == 1)
        #expect(WindowMatch.score(
            saved, title: "Renamed", document: saved.document, windowID: 12, launchDate: nil
        ) == 2)
    }

    @Test func reusedWindowIDsNeedTheSameAppLaunch() {
        var saved = template().windows[0]
        saved.document = nil
        #expect(WindowMatch.score(saved, title: "Other", document: nil, windowID: 42,
                                         launchDate: Date(timeIntervalSince1970: 200)) == 0)
        #expect(WindowMatch.score(
            saved, title: "Other", document: nil, windowID: 42, launchDate: saved.launchDate
        ) == 3)
    }

    @Test func libraryPersistsRenamesAndDeletes() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("templates.json")
        let library = TemplateLibrary(url: url)
        var saved = template()
        #expect(library.save(saved))
        saved.name = "Research"
        #expect(library.save(saved))
        let reloaded = TemplateLibrary(url: url)
        #expect(reloaded.templates.count == 1)
        #expect(reloaded.templates[0].name == "Research")
        reloaded.delete(saved)
        #expect(TemplateLibrary(url: url).templates.isEmpty)
    }

    @Test func libraryRejectsEmptyAndDuplicateNames() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = TemplateLibrary(url: directory.appendingPathComponent("templates.json"))
        let saved = template()
        #expect(library.save(saved))
        var duplicate = template()
        duplicate.name = " writing "
        #expect(!library.save(duplicate))
        duplicate.name = " \n "
        #expect(!library.save(duplicate))
        #expect(library.templates.count == 1)
    }

    @Test func unreadableLibrariesAreNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("templates.json")
        let data = Data("invalid saved data".utf8)
        try data.write(to: url)
        let library = TemplateLibrary(url: url)
        #expect(!library.save(template()))
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func failedWritesDoNotChangeTheLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = TemplateLibrary(url: directory)
        #expect(!library.save(template()))
        #expect(library.templates.isEmpty)
        #expect(library.error != nil)
    }
}
