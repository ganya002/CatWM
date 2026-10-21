import AppKit
@testable import ouch
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
}
