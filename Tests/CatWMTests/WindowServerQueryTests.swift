import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WindowServerQueryTests {
    private func record(_ id: CGWindowID, spaces: Set<UInt64>) -> WindowServerQuery.Record {
        .init(info: CGWindowInfo(id: id, pid: 7, bounds: CGRect(x: 0, y: 0, width: 300, height: 200)), spaces: spaces)
    }

    @Test func nativeObservationIDsKeepOrderAndAnEmptySnapshot() {
        for ids: [CGWindowID] in [[9, 3, 7], []] {
            let found = WindowServerQuery.observationWindowIDs([.optionOnScreenOnly, .excludeDesktopElements],
                onScreen: { ids }, fallback: { _ in
                    Issue.record("Unexpected public window list read"); return nil
                })
            #expect(found == ids)
        }
    }

    @Test func unavailableNativeObservationIDsUseThePublicFallback() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        var reads: [CGWindowListOption] = []
        let found = WindowServerQuery.observationWindowIDs(options, onScreen: { nil }, fallback: {
            reads.append($0)
            return [8, 2]
        })
        #expect(found == [8, 2] && reads == [options])
    }

    @Test(arguments: [
        CGWindowListOption.optionAll,
        .optionOnScreenOnly,
        [.optionAll, .excludeDesktopElements],
        .optionIncludingWindow
    ])
    func otherWindowListsKeepTheirPublicSemantics(_ options: CGWindowListOption) {
        var reads: [CGWindowListOption] = []
        let found = WindowServerQuery.observationWindowIDs(options, onScreen: {
            Issue.record("Unexpected native on-screen list read"); return []
        }, fallback: { reads.append($0); return [8, 2] })
        #expect(found == [8, 2] && reads == [options])
    }

    @Test func observationPreservesTheSeparateStackingOrders() throws {
        let records: WindowServerQuery.Records = [1: record(1, spaces: [11]), 2: record(2, spaces: [12]),
                                                  3: record(3, spaces: [11, 12])]
        var queried = Set<CGWindowID>()
        let found = try #require(WindowServerQuery.observation(known: [4], list: {
            $0.contains(.optionOnScreenOnly) ? [2, 1] : [3, 1, 2]
        }, query: {
            queried = $0
            return records
        }, fallback: { _ in [] }, managedSpaces: { [11: 11, 12: 12] }))
        #expect(found.windows.map(\.id) == [2, 1])
        #expect(found.allWindows.map(\.id) == [3, 1, 2])
        #expect(found.spaces == [1: [11], 2: [12], 3: [11, 12], 4: []])
        #expect(queried == [1, 2, 3, 4])
    }

    @Test func observationKeepsNewVisibleWindowsAndOmitsNonAppLayers() throws {
        let records: WindowServerQuery.Records = [1: record(1, spaces: [11]), 2: record(2, spaces: [11]),
                                                  3: WindowServerQuery.Record(info: nil, spaces: [11])]
        let found = try #require(WindowServerQuery.observation(known: [], list: {
            $0.contains(.optionOnScreenOnly) ? [2, 1, 3] : [3, 1]
        }, query: { _ in records }, managedSpaces: { [11: 11] }))
        #expect(found.windows.map(\.id) == [2, 1])
        #expect(found.allWindows.map(\.id) == [1])
        #expect(found.spaces == [1: [11], 2: [11]])
    }

    @Test func unavailableListsOrQueryLeaveTheFallbackPathAvailable() {
        let missingList = WindowServerQuery.observation(known: [], list: { _ in nil })
        let missingQuery = WindowServerQuery.observation(known: [], list: { _ in [] }, query: { _ in nil })
        #expect(missingList == nil && missingQuery == nil)
    }

    @Test func completeBatchPreservesStickyAndUnassignedWindows() {
        let batch: WindowServerQuery.Membership = [1: [11], 2: [11, 12], 3: []]
        var individualReads = 0
        let found = WindowServerQuery.memberships(for: [1, 2, 3], query: { _ in batch }, fallback: { _ in
            individualReads += 1
            return [99]
        }, managedSpaces: { [11: 11, 12: 12] })
        #expect(found == batch && individualReads == 0)
    }

    @Test func partialBatchReadsOnlyMissingWindows() {
        var read: [CGWindowID] = []
        let found = WindowServerQuery.memberships(for: [1, 2], query: { _ in [1: [11]] }, fallback: {
            read.append($0)
            return [12]
        }, managedSpaces: { [11: 11] })
        #expect(found == [1: [11], 2: [12]])
        #expect(read == [2])
    }

    @Test func unavailableBatchUsesTheExistingReader() {
        var read = Set<CGWindowID>()
        let found = WindowServerQuery.memberships(for: [1, 2], query: { _ in nil }, fallback: {
            read.insert($0)
            return $0 == 1 ? [11] : []
        })
        #expect(found == [1: [11], 2: []] && read == [1, 2])
    }

    @Test func unrelatedBatchEntriesCannotAddWindows() {
        let found = WindowServerQuery.memberships(for: [1], query: { _ in [1: [11], 2: [12]] },
                                                  managedSpaces: { [11: 11, 12: 12] })
        #expect(found == [1: [11]])
    }

    @Test func emptyRequestDoesNotReadTheServer() {
        var reads = 0
        let found = WindowServerQuery.memberships(for: [], query: { _ in reads += 1; return [:] }, fallback: { _ in
            reads += 1
            return []
        }, managedSpaces: { reads += 1; return [:] })
        #expect(found.isEmpty && reads == 0)
    }

    @Test func fullscreenTilesAndWallSpacesUseTheirManagedDesktop() throws {
        let raw: WindowServerQuery.Membership = [1: [398], 2: [397, 4], 3: [398, 396], 4: []]
        let managed: [UInt64: UInt64] = [4: 4, 396: 396, 397: 396, 398: 396]
        let found = WindowServerQuery.memberships(for: [1, 2, 3, 4], query: { _ in raw }, fallback: { _ in
            Issue.record("Unexpected individual membership read")
            return []
        }, managedSpaces: { managed })
        #expect(found == [1: [396], 2: [396, 4], 3: [396], 4: []])
        let observation = try #require(WindowServerQuery.observation(known: [], list: { _ in [1] },
            query: { _ in [1: record(1, spaces: [398])] }, managedSpaces: { managed }))
        #expect(observation.spaces == [1: [396]])
    }

    @Test func anUnknownRawSpaceUsesTheCurrentIndividualMembership() {
        var read = Set<CGWindowID>()
        let found = WindowServerQuery.memberships(for: [1, 2, 3], query: { _ in
            [1: [11], 2: [398], 3: []]
        }, fallback: { id in
            read.insert(id)
            return [396]
        }, managedSpaces: { [11: 11] })
        #expect(found == [1: [11], 2: [396], 3: []] && read == [2])
    }

    @Test func anUnavailableManagedCatalogUsesTheIndividualMembership() {
        var read = Set<CGWindowID>()
        let found = WindowServerQuery.memberships(for: [1, 2], query: { _ in [1: [398], 2: []] }, fallback: { id in
            read.insert(id)
            return [396]
        }, managedSpaces: { nil })
        #expect(found == [1: [396], 2: []] && read == [1])
    }

    @Test func frameReadsDoNotInventMissingOrUnrequestedWindows() {
        let frames = WindowServerQuery.frames(for: [1, 2, 3], query: { _ in
            [1: record(1, spaces: [11]), 2: .init(info: nil, spaces: []), 4: record(4, spaces: [11])]
        })
        #expect(frames?.keys.sorted() == [1])
        #expect(frames?[1] == CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(WindowServerQuery.frames(for: [1], query: { _ in nil }) == nil)
        let empty = WindowServerQuery.frames(for: [], query: { _ in
            Issue.record("Unexpected server read"); return nil
        })
        #expect(empty?.isEmpty == true)
    }
}
