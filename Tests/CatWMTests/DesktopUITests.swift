import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct DesktopUITests {
    private let left = CGRect(x: -1200, y: 0, width: 1200, height: 800)
    private let right = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    private func window(_ frame: CGRect, owner: pid_t = 7, layer: Int = 0) -> [String: Any] {
        [kCGWindowOwnerPID as String: owner, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }

    @Test func missionControlOnEitherDisplayBlocksTiling() {
        for frame in [left, right] {
            #expect(DesktopUI.isBusy([window(frame)], ownedBy: [7], on: [left, right]))
        }
    }

    @Test func normalAppWindowsAndTheMenuBarDoNotBlockTiling() {
        let windows = [window(left, owner: 8), window(right, layer: 20), window(left, layer: -1)]
        #expect(!DesktopUI.isBusy(windows, ownedBy: [7], on: [left, right]))
    }

    @Test func systemWindowsOutsideTheDisplaysDoNotBlockTiling() {
        let windows = [window(right.offsetBy(dx: 2000, dy: 0))]
        #expect(!DesktopUI.isBusy(windows, ownedBy: [7], on: [left, right]))
    }

    @Test func coverageIsMeasuredAgainstEachDisplay() {
        let small = right.insetBy(dx: right.width * 0.06, dy: right.height * 0.06)
        let large = right.insetBy(dx: right.width * 0.04, dy: right.height * 0.04)
        #expect(!DesktopUI.isBusy([window(small)], ownedBy: [7], on: [left, right]))
        #expect(DesktopUI.isBusy([window(large)], ownedBy: [7], on: [left, right]))
    }

    @Test func missingSystemOwnersKeepTheBusyCheckConservative() {
        #expect(DesktopUI.isBusy([], ownedBy: [], on: [left, right]))
        #expect(!DesktopUI.isBusy([], ownedBy: [], on: []))
    }

    @Test func nativeMetadataKeepsTheDisplayAndLayerRules() {
        func native(_ frame: CGRect, pid: pid_t = 7, level: Int = 0) -> WindowServerQuery.WindowInfo {
            .init(id: 1, pid: pid, level: level, bounds: frame)
        }
        func busy(_ windows: [WindowServerQuery.WindowInfo]) -> Bool {
            DesktopUI.isBusy(windows, ownedBy: [7], on: [left, right]) {
                Issue.record("Unexpected fallback"); return []
            }
        }
        #expect(busy([native(left)]))
        #expect(busy([native(right)]))
        #expect(!busy([native(left, pid: 8), native(right, level: 20), native(left, level: -1)]))
        #expect(!busy([native(right.offsetBy(dx: 2000, dy: 0))]))
        #expect(!busy([native(right.insetBy(dx: right.width * 0.06, dy: right.height * 0.06))]))
        #expect(busy([native(right.insetBy(dx: right.width * 0.04, dy: right.height * 0.04))]))
    }

    @Test func unavailableMetadataAndUnattributedLargeWindowsUseTheExistingReader() {
        let unknown = WindowServerQuery.WindowInfo(id: 1, pid: 0, level: 0, bounds: right)
        for native in [nil, [unknown]] as [[WindowServerQuery.WindowInfo]?] {
            var reads = 0
            let busy = DesktopUI.isBusy(native, ownedBy: [7], on: [right]) {
                reads += 1
                return [window(right)]
            }
            #expect(busy && reads == 1)
            #expect(!DesktopUI.isBusy(native, ownedBy: [7], on: [right], fallback: { [] }))
        }
    }

    @Test func unattributedWallpaperAndSmallSystemWindowsDoNotNeedTheFallback() {
        let windows: [WindowServerQuery.WindowInfo] = [
            .init(id: 1, pid: 0, level: -1, bounds: right),
            .init(id: 2, pid: 0, level: 24, bounds: CGRect(x: 0, y: 0, width: 1600, height: 38))
        ]
        #expect(!DesktopUI.isBusy(windows, ownedBy: [7], on: [right]) {
            Issue.record("Unexpected fallback"); return []
        })
        #expect(DesktopUI.isBusy(windows, ownedBy: [], on: [right], fallback: { [] }))
        #expect(!DesktopUI.isBusy(windows, ownedBy: [], on: [], fallback: { [] }))
    }
}
