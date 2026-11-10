import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct WindowServerQueryIntegrationTests {
    @Test func menuBackgroundBatchMatchesTheIndividualReader() throws {
        _ = NSApplication.shared
        let snapshot = try #require(Spaces.snapshot())
        let levels: Set<Int32> = [CGWindowLevelForKey(.desktopIconWindow) + 1,
                                  CGWindowLevelForKey(.desktopWindow) - 1]
        for display in snapshot.displays {
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            for space in spaces {
                let id = try #require(space["ManagedSpaceID"] as? UInt64)
                let all = DesktopMenuBarNative.windows(on: id)
                let filtered = DesktopMenuBarNative.windows(on: id, levels: levels)
                #expect(filtered.map(\.id) == all.filter { levels.contains($0.level) }.map(\.id))
                for window in all {
                    let legacy = try #require(DesktopMenuBarNative.info(window.id))
                    #expect(window.level == legacy.level)
                    #expect(window.owner == legacy.owner)
                    #expect(window.frame == legacy.frame)
                }
            }
        }
    }

    @Test func metadataIgnoresStaleIDsAndDoesNotAddUnrequestedWindows() throws {
        _ = NSApplication.shared
        let live = try #require(CGWindowInfo.onScreen().first?.id)
        let found = try #require(WindowServerQuery.metadata(for: [live, 0, .max, live]))
        #expect(found.map(\.id) == [live])
        #expect(WindowServerQuery.metadata(for: [])?.isEmpty == true)
    }

    @Test func desktopMetadataMatchesThePublicReader() throws {
        _ = NSApplication.shared
        let found = try #require(WindowServerQuery.onScreenWindows())
        let publicWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let entries = publicWindows.compactMap { window -> (CGWindowID, [String: Any])? in
            (window[kCGWindowNumber as String] as? CGWindowID).map { ($0, window) }
        }
        let expected = Dictionary(uniqueKeysWithValues: entries)
        #expect(Set(found.map(\.id)) == Set(expected.keys))
        for window in found {
            let legacy = try #require(expected[window.id])
            #expect(window.level == legacy[kCGWindowLayer as String] as? Int)
            let bounds = try #require(legacy[kCGWindowBounds as String] as? [String: Any])
            #expect(window.bounds == CGRect(dictionaryRepresentation: bounds as CFDictionary))
            if window.pid != 0 { #expect(window.pid == legacy[kCGWindowOwnerPID as String] as? pid_t) }
        }
        let pids = Set(DesktopUI.owners.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .map(\.processIdentifier))
        let frames = Screen.all().map(\.frame)
        let nativeBusy = DesktopUI.isBusy(found, ownedBy: pids, on: frames, fallback: { publicWindows })
        #expect(nativeBusy == DesktopUI.isBusy(publicWindows, ownedBy: pids, on: frames))
    }

    @Test func batchMatchesTheIndividualReaderForLiveWindows() {
        _ = NSApplication.shared
        let ids = Set(CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements]).map(\.id))
        #expect(!ids.isEmpty)
        var fallbackReads = 0
        let found = WindowServerQuery.memberships(for: ids, fallback: {
            fallbackReads += 1
            return Spaces.of(window: $0)
        })
        #expect(fallbackReads == 0)
        for id in ids { #expect(found[id] == Set(Spaces.of(window: id))) }
    }

    @Test func staleWindowIDsDoNotDiscardLiveMemberships() throws {
        _ = NSApplication.shared
        let live = try #require(CGWindowInfo.onScreen().first?.id)
        let ids: Set<CGWindowID> = [live, 0, .max]
        var fallbackReads = Set<CGWindowID>()
        let found = WindowServerQuery.memberships(for: ids, fallback: {
            fallbackReads.insert($0)
            return Spaces.of(window: $0)
        })
        #expect(found[live] == Set(Spaces.of(window: live)))
        #expect(found[0]?.isEmpty == true && found[.max]?.isEmpty == true)
        #expect(fallbackReads == [0, .max])
    }

    @Test func completeObservationMatchesWindowInfoAndStackingOrder() throws {
        _ = NSApplication.shared
        let found = try #require(WindowServerQuery.observation(known: []))
        let visible = CGWindowInfo.onScreen()
        let all = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements])
        #expect(found.windows.map(\.id) == visible.map(\.id))
        #expect(found.allWindows.map(\.id) == all.map(\.id))
        let expected = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        for info in found.allWindows {
            #expect(info.pid == expected[info.id]?.pid)
            #expect(info.bounds == expected[info.id]?.bounds)
            #expect(found.spaces[info.id] == Set(Spaces.of(window: info.id)))
        }
    }
}
