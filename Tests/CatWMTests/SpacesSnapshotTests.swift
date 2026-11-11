import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct SpacesSnapshotTests {
    private func space(_ id: UInt64, type: Int = 0) -> [String: Any] {
        ["ManagedSpaceID": id, "type": type]
    }

    @Test func keepsEachDisplayAndItsCurrentDesktopInTheSameSnapshot() throws {
        let snapshot = Spaces.Snapshot(displays: [
            ["Display Identifier": "left", "Current Space": ["ManagedSpaceID": UInt64(12)],
             "Spaces": [space(11), space(12, type: 4)]],
            ["Display Identifier": "right", "Current Space": ["ManagedSpaceID": UInt64(21)],
             "Spaces": [space(21)]]
        ])
        let left = try #require(snapshot.list(display: "left"))
        #expect(left.ids == [11, 12])
        #expect(left.desktops == [0])
        #expect(left.current == 1)
        let right = try #require(snapshot.list(display: "right"))
        #expect(right.ids == [21])
        #expect(right.current == 0)
        #expect(snapshot.list(display: "disconnected") == nil)
    }

    @Test func sharesARememberedSnapshotOnlyUntilItIsTooOld() {
        var remembered = Spaces.Remembered()
        #expect(remembered.fresh(at: 100) == nil)
        remembered.remember(Spaces.Snapshot(displays: [["Display Identifier": "left", "Spaces": [space(11)]]]), at: 100)
        #expect(remembered.fresh(at: 100 + Spaces.Remembered.maxAge / 2)?.list(display: "left")?.ids == [11])
        #expect(remembered.fresh(at: 100 + Spaces.Remembered.maxAge * 2) == nil)
        remembered.remember(nil, at: 101)
        #expect(remembered.fresh(at: 101) == nil)
    }

    @Test func keepsTheSingleDisplayIdentifierFallback() throws {
        let snapshot = Spaces.Snapshot(displays: [
            ["Display Identifier": "Main", "Spaces": [space(11)]]
        ])
        let info = try #require(snapshot.list(display: "screen-uuid"))
        #expect(info.ids == [11])
        #expect(info.current == nil)
    }

    @Test func doesNotTreatAMalformedSecondDisplayAsASingleDisplay() {
        let snapshot = Spaces.Snapshot(displays: [
            ["Display Identifier": "left", "Spaces": [space(11)]],
            ["Display Identifier": "right"]
        ])
        #expect(snapshot.list(display: "right") == nil)
        #expect(snapshot.list(display: "unknown") == nil)
    }

    @Test func fullscreenTilesAndWallSpacesKeepTheirManagedDesktopIdentity() {
        let fullscreen: [String: Any] = [
            "ManagedSpaceID": UInt64(396), "id64": UInt64(396),
            "WallSpace": ["id64": UInt64(397), "ManagedSpaceID": UInt64(396)],
            "TileLayoutManager": ["TileSpaces": [
                ["id64": UInt64(398), "ManagedSpaceID": UInt64(396)], ["id64": UInt64(399)]
            ]]
        ]
        let snapshot = Spaces.Snapshot(displays: [
            ["Spaces": [space(4), fullscreen]], ["Spaces": [space(21)]]
        ])
        #expect(snapshot.managedSpaceIDs == [4: 4, 21: 21, 396: 396, 397: 396, 398: 396, 399: 396])
    }

    @Test func malformedSpaceIdentitiesDoNotInventAnAlias() {
        let snapshot = Spaces.Snapshot(displays: [["Spaces": [
            ["id64": UInt64(9)], ["ManagedSpaceID": UInt64(0), "id64": UInt64(10)],
            ["ManagedSpaceID": UInt64(11), "id64": UInt64(0)]
        ]]])
        #expect(snapshot.managedSpaceIDs == [11: 11])
    }
}
