import AppKit
@testable import CatWM
import Testing

@MainActor @Suite struct ScopeClaimsTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-claims-\(UUID().uuidString)")

    func write(_ claim: ScopeClaim, id: String, modified: Date? = nil) throws {
        let file = folder.appendingPathComponent("\(id)/scope")
        let files = FileManager.default
        try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(claim.text.utf8).write(to: file)
        if let modified { try files.setAttributes([.modificationDate: modified], ofItemAtPath: file.path) }
    }

    @Test func aClaimReadsBackTheTextThatItWrites() {
        let claim = ScopeClaim(owner: 7, scope: WindowScope(pids: [30, 4], display: "ABC-1"))
        #expect(claim.text == "7\npids:4,30;display:ABC-1\n")
        #expect(ScopeClaim(claim.text) == claim)
        #expect(ScopeClaim("7\n") == nil)
        #expect(ScopeClaim("x\npids:4\n") == nil)
        #expect(ScopeClaim("7\npids:\n") == nil)
    }

    @Test func aClaimOfALiveOwnerHidesItsPidsAndADeadOwnerDoesNot() throws {
        try write(ScopeClaim(owner: 1, scope: WindowScope(pids: [10, 11])), id: "live")
        try write(ScopeClaim(owner: 2, scope: WindowScope(pids: [20])), id: "dead")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("noscope"),
                                                withIntermediateDirectories: true)
        let claims = ScopeClaims(folder: folder, alive: { $0 == 1 })
        #expect(claims.claimedPids() == [10, 11])
    }

    @Test func claimsAreReadAgainOnlyWhenAFileChanges() throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        try write(ScopeClaim(owner: 1, scope: WindowScope(pids: [10])), id: "a", modified: date)
        let claims = ScopeClaims(folder: folder, alive: { _ in true })
        #expect(claims.claimedPids() == [10])
        try write(ScopeClaim(owner: 1, scope: WindowScope(pids: [12])), id: "a", modified: date)
        #expect(claims.claimedPids() == [10])
        try write(ScopeClaim(owner: 1, scope: WindowScope(pids: [12])), id: "a", modified: date + 1)
        #expect(claims.claimedPids() == [12])
        try FileManager.default.removeItem(at: folder.appendingPathComponent("a"))
        #expect(claims.claimedPids().isEmpty)
    }

    @Test func anUnscopedScannerHidesTheClaimedPids() async throws {
        try write(ScopeClaim(owner: 1, scope: WindowScope(pids: [20])), id: "test")
        let windows = [CGWindowInfo(id: 1, pid: 10, bounds: .zero), CGWindowInfo(id: 2, pid: 20, bounds: .zero)]
        let scanner = WindowScanner(readDesktop: { _ in
            WindowServerObservation(windows: windows, allWindows: windows)
        }, readApplications: {
            [10, 20].map { RunningApplicationSnapshot(pid: $0, bundleID: nil, regular: true, hidden: false) }
        }, claims: ScopeClaims(folder: folder, alive: { _ in true }))
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: []) { continuation.resume() }
        }
        #expect(scanner.desktop.windows.map(\.pid) == [10])
        #expect(scanner.desktop.allWindows.map(\.pid) == [10])
        #expect(scanner.applications.map(\.pid) == [10])
    }
}
