import AppKit
@testable import CatWM
import Testing

@Suite struct NativeWorkspaceCatalogTests {
    @Test func adoptsDesktopsAcrossDisplaysWithUniqueNumbers() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "left", spaces: [11, 12]), .init(id: "right", spaces: [21, 22])])
        #expect(catalog.entry("1") == .init(name: "1", display: "left", space: 11))
        #expect(catalog.entry("3") == .init(name: "3", display: "right", space: 21))
        #expect(Set(catalog.entries.map(\.name)).count == 4)
    }

    @Test func perDisplayNumbersFollowDesktopOrder() {
        var catalog = NativeWorkspaceCatalog()
        catalog.perDisplay = true
        catalog.synchronize([.init(id: "left", spaces: [11, 12]), .init(id: "right", spaces: [21, 22])])
        #expect(catalog.entry("left/1")?.space == 11)
        #expect(catalog.entry("right/1")?.space == 21)
        #expect(catalog.freeNumber(on: "right") == "right/3")
        catalog.synchronize([.init(id: "left", spaces: [12, 11]), .init(id: "right", spaces: [22])])
        #expect(catalog.entry("left/1")?.space == 12)
        #expect(catalog.entry("right/1")?.space == 22)
        #expect(catalog.entry("right/2") == nil)
        #expect(WorkspaceKey.number("right/2") == "2")
        #expect(WorkspaceKey.display("right/2") == "right")
    }

    @Test func newDesktopGoesBeforeTheNextHigherWorkspace() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "left", spaces: [11, 12, 13]), .init(id: "right", spaces: [21])])
        catalog.bind("7", to: 13, on: "left")
        #expect(catalog.successor(of: "5", on: "left") == 13)
        #expect(catalog.successor(of: "8", on: "left") == nil)
        #expect(catalog.successor(of: "8", on: "right") == nil)
        catalog.perDisplay = true
        #expect(catalog.successor(of: "5", on: "left") == nil)
    }

    @Test func namesFollowDesktopIdentityWhenNativeOrderChanges() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 13])])
        catalog.synchronize([.init(id: "screen", spaces: [13, 11, 12])])
        #expect(catalog.entry("1")?.space == 11)
        #expect(catalog.step(from: "1", by: 1) == "2")
        #expect(catalog.step(from: "2", by: 1) == "3")
        #expect(catalog.step(from: "3", by: 1) == nil)
        #expect(catalog.step(from: "1", by: -1) == nil)
    }

    @Test func stepFollowsWorkspaceNumbersNotDesktopOrder() {
        var catalog = NativeWorkspaceCatalog()
        catalog.saved = ["1": 11, "2": 14, "3": 12, "10": 13]
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 13, 14])])
        #expect(catalog.step(from: "1", by: 1) == "2")
        #expect(catalog.step(from: "2", by: 1) == "3")
        #expect(catalog.step(from: "3", by: 1) == "10")
        #expect(catalog.step(from: "10", by: -2) == "2")
    }

    @Test func extremeRelativeStepsStayOutsideTheCatalog() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 13])])
        #expect(catalog.step(from: "2", by: Int.max) == nil)
        #expect(catalog.step(from: "2", by: Int.min) == nil)
    }

    @Test func removedDesktopDoesNotRenameOtherDesktops() {
        var catalog = NativeWorkspaceCatalog()
        catalog.saved = ["1": 11, "2": 12, "3": 13]
        catalog.synchronize([.init(id: "screen", spaces: [11, 13, 14])])
        #expect(catalog.entry("3")?.space == 13)
        #expect(catalog.entry("2")?.space == 14)
        #expect(catalog.entries.allSatisfy { $0.space != 12 })
    }

    @Test func disconnectedDisplayKeepsItsWorkspaceNames() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "laptop", spaces: [11, 12]), .init(id: "monitor", spaces: [21])])
        catalog.synchronize([.init(id: "laptop", spaces: [11, 12, 13])])
        #expect(catalog.entry("3") == nil)
        #expect(catalog.entry("4")?.space == 13)
        catalog.synchronize([.init(id: "laptop", spaces: [11, 12, 13]), .init(id: "monitor", spaces: [21])])
        #expect(catalog.entry("3") == .init(name: "3", display: "monitor", space: 21))
        catalog.synchronize([.init(id: "laptop", spaces: [11, 12, 13]), .init(id: "monitor", spaces: [22])])
        #expect(catalog.entry("3")?.space == 22)
    }

    @Test func namesFollowTheDesktopUUIDWhenItsSpaceIDChanges() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "screen", spaces: [11, 12], uuids: [11: "A", 12: "B"])])
        catalog.bind("writing", to: 13, on: "screen")
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 13], uuids: [11: "A", 12: "B", 13: "C"])])
        #expect(catalog.uuids == ["1": "A", "2": "B", "writing": "C"])
        catalog.synchronize([.init(id: "screen", spaces: [42, 41, 13], uuids: [41: "A", 42: "B", 13: "C"])])
        #expect(catalog.entry("1")?.space == 41)
        #expect(catalog.entry("2")?.space == 42)
        #expect(catalog.entry("writing")?.space == 13)
    }

    @Test func newNamedWorkspaceKeepsItsCreatedDesktop() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "screen", spaces: [11, 12])])
        catalog.bind("writing", to: 13, on: "screen")
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 13])])
        #expect(catalog.entry("writing")?.space == 13)
        #expect(catalog.entry("1")?.space == 11)
        #expect(catalog.entry("2")?.space == 12)
    }

    @Test func corruptDuplicateBindingsCannotCreateDuplicateWorkspaceRows() {
        var catalog = NativeWorkspaceCatalog()
        catalog.saved = ["1": 11, "2": 11, "missing": 99]
        catalog.synchronize([.init(id: "screen", spaces: [0, 11, 12])])
        #expect(catalog.entries.count == 2)
        #expect(Set(catalog.entries.map(\.space)) == [11, 12])
        #expect(catalog.entry("missing") == nil)
    }

    @Test func desktopKeepsItsNameUntilRemovalIsConfirmed() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 13], current: 11)])
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 13], current: 11)])
        #expect(catalog.entry("3")?.space == 13)
        #expect(catalog.freeNumber(on: "screen") == "4")
        catalog.synchronize([.init(id: "screen", spaces: [11, 12], current: 11)])
        #expect(catalog.entry("3") == nil)
        #expect(catalog.freeNumber(on: "screen") == "3")
        catalog.bind("3", to: 14, on: "screen")
        catalog.synchronize([.init(id: "screen", spaces: [11, 12, 14], current: 11)])
        #expect(catalog.entry("3")?.space == 14)
    }

    @Test func onlyConfirmedRemovalsAreReported() {
        var catalog = NativeWorkspaceCatalog()
        catalog.synchronize([.init(id: "left", spaces: [11, 12], uuids: [11: "A", 12: "B"]),
                             .init(id: "right", spaces: [21])])
        let reordered = catalog.synchronize([
            .init(id: "left", spaces: [42, 41], uuids: [41: "A", 42: "B"]),
            .init(id: "right", spaces: [21])
        ])
        #expect(reordered.isEmpty)
        #expect(catalog.synchronize([.init(id: "left", spaces: [41, 42])]).isEmpty)
        #expect(catalog.saved["3"] == 21)
        #expect(catalog.synchronize([.init(id: "left", spaces: [41, 43])]) == ["2"])
        #expect(catalog.entry("2")?.space == 43)
    }

    @Test(arguments: [false, true]) @MainActor
    func anExternallyRemovedDesktopDoesNotDonateItsLabelAndLayout(replace: Bool) throws {
        let screen = try #require(Screen.all().first)
        let manager = WindowManager(config: .parse(defaultText))
        manager.config.workspacesPerDisplay = false
        manager.desktops.nativeCatalog.synchronize([.init(id: screen.uuid, spaces: [11, 12, 13])])
        manager.labels = ["2": "Mail", "3": "Code"]
        manager.state(workspace: "2").layout = .floating
        manager.lastFocused["2"] = 7
        let spaces: [UInt64] = replace ? [13, 11, 14] : [13, 11]
        let snapshot = Spaces.Snapshot(displays: [[
            "Display Identifier": screen.uuid,
            "Spaces": spaces.map { ["ManagedSpaceID": $0, "type": 0] as [String: Any] }
        ]])
        manager.updateNativeCatalog([screen], snapshot: snapshot)
        #expect(manager.desktops.nativeCatalog.entry("2")?.space == (replace ? 14 : nil))
        #expect(manager.labels["2"] == nil)
        #expect(manager.states["2"] == nil)
        #expect(manager.lastFocused["2"] == nil)
        #expect(manager.labels["3"] == "Code")
    }

    @Test func ctrlDefaultsRespectConfiguredCommands() {
        let config = Config.parse("bind = CTRL, 1, layout, floating\nbind = ALT, 2, workspace, 2")
        let bindings = config.workspaceBindings
        let ctrlOne = bindings.filter { $0.mods == .maskControl && $0.keyCode == 18 && $0.submap.isEmpty }
        #expect(ctrlOne.count == 1)
        #expect(ctrlOne.first?.dispatcher == "layout")
        #expect(bindings.contains { $0.mods == .maskAlternate && $0.keyCode == 19 })
        #expect(bindings.contains { $0.mods == .maskControl && $0.keyCode == 29 && $0.arg == "10" })
        #expect(bindings.contains { $0.mods == .maskControl && $0.keyCode == 123 && $0.arg == "r-1" })
        #expect(bindings.contains { $0.mods == .maskControl && $0.keyCode == 124 && $0.arg == "r+1" })
        let move: CGEventFlags = [.maskControl, .maskShift]
        #expect(bindings.contains { $0.mods == move && $0.keyCode == 18 && $0.dispatcher == "movetoworkspace" })
        #expect(bindings.contains { $0.mods == move && $0.keyCode == 124 && $0.arg == "r+1" })
    }

    @Test func unmanagedNativeModeDoesNotInterceptCtrlDefaults() {
        var config = Config()
        config.virtualWorkspaces = false
        #expect(config.workspaceBindings.isEmpty)
    }
}
