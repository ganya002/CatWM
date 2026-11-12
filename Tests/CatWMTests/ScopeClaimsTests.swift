import AppKit
@testable import CatWM
@testable import CatWMKit
import os
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

    @Test func claimsAreReadAgainOnlyWhenTheInstancesFolderChanges() throws {
        let home = folder.appendingPathComponent("home")
        let paths = try #require(InstancePaths(id: "a", home: home))
        try paths.writeClaim(ScopeClaim(owner: 1, scope: WindowScope(pids: [10])))
        let claims = ScopeClaims(folder: paths.instancesFolder, alive: { _ in true })
        #expect(claims.claimedPids() == [10])
        try Data(ScopeClaim(owner: 1, scope: WindowScope(pids: [11])).text.utf8).write(to: paths.scopeFile)
        #expect(claims.claimedPids() == [10])
        try paths.writeClaim(ScopeClaim(owner: 1, scope: WindowScope(pids: [12])))
        #expect(claims.claimedPids() == [12])
        try paths.removeClaim()
        #expect(claims.claimedPids().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.instancesFolder.path) == ["a"])
    }

    @Test func aDeadOwnerIsCheckedOnEachReadWithoutReadingTheFilesAgain() throws {
        try write(ScopeClaim(owner: 1, scope: WindowScope(pids: [10])), id: "a")
        let running = OSAllocatedUnfairLock(initialState: true)
        let claims = ScopeClaims(folder: folder, alive: { _ in running.withLock { $0 } })
        #expect(claims.claimedPids() == [10])
        running.withLock { $0 = false }
        #expect(claims.claimedPids().isEmpty)
    }

    @Test func aNewClaimReleasesTheWindowsThatTheManagerAlreadyHas() async throws {
        let scanner = WindowScanner(readDesktop: { _ in WindowServerObservation() }, readApplications: { [] },
                                    claims: ScopeClaims(folder: folder, alive: { _ in true }))
        let manager = WindowManager(config: Config(), scanner: scanner)
        let claimed = Window(id: 31, element: AXUIElementCreateApplication(4242), pid: 4242, bundleID: nil)
        let other = Window(id: 32, element: AXUIElementCreateApplication(4243), pid: 4243, bundleID: nil)
        manager.windows = [31: claimed, 32: other]
        manager.observing[4242] = UUID()
        manager.releaseClaimedApps()
        #expect(manager.windows.count == 2)
        try write(ScopeClaim(owner: 1, scope: WindowScope(pids: [4242])), id: "test")
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: []) { continuation.resume() }
        }
        manager.releaseClaimedApps()
        #expect(manager.windows.keys.sorted() == [32])
        #expect(manager.observing[4242] == nil)
        manager.observe(pid: 4242)
        #expect(manager.observing[4242] == nil)
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

    func claimedScanner(_ claims: ScopeClaims) -> WindowScanner {
        let windows = [CGWindowInfo(id: 31, pid: 4242, bounds: .zero)]
        return WindowScanner(readDesktop: { _ in
            WindowServerObservation(windows: windows, allWindows: windows)
        }, readApplications: {
            [RunningApplicationSnapshot(pid: 4242, bundleID: nil, regular: true, hidden: false)]
        }, claims: claims)
    }

    func scanDesktop(_ scanner: WindowScanner) async {
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: []) { continuation.resume() }
        }
    }

    @Test(.timeLimit(.minutes(1))) func aClaimChangeStartsAScanWithoutAnyOtherEvent() async throws {
        let paths = try #require(InstancePaths(id: "a", home: folder))
        let scanner = claimedScanner(ScopeClaims(folder: paths.instancesFolder, alive: { _ in true }))
        let manager = WindowManager(config: Config(), scanner: scanner)
        manager.windows = [31: Window(id: 31, element: AXUIElementCreateApplication(4242), pid: 4242, bundleID: nil)]
        let (changes, change) = AsyncStream.makeStream(of: Void.self)
        var changed = changes.makeAsyncIterator()
        scanner.watchClaims { _ in change.yield() }

        try paths.writeClaim(ScopeClaim(owner: 1, scope: WindowScope(pids: [4242])))
        await changed.next()
        await scanDesktop(scanner)
        manager.releaseClaimedApps()
        #expect(manager.windows.isEmpty)
        #expect(scanner.desktop.windows.isEmpty)
        #expect(!scanner.keeps(4242))

        try paths.removeClaim()
        await changed.next()
        await scanDesktop(scanner)
        #expect(scanner.desktop.windows.map(\.pid) == [4242])
        #expect(scanner.applications.map(\.pid) == [4242])
        #expect(scanner.keeps(4242))
    }

    @Test(.timeLimit(.minutes(1))) func theExitOfAClaimOwnerStartsAScanAndTheScanKeepsItsPids() async throws {
        let paths = try #require(InstancePaths(id: "a", home: folder))
        let input = Pipe()
        let owner = Process()
        owner.executableURL = URL(fileURLWithPath: "/bin/cat")
        owner.standardInput = input
        try owner.run()
        defer {
            try? input.fileHandleForWriting.close()
            owner.waitUntilExit()
        }
        try paths.writeClaim(ScopeClaim(owner: owner.processIdentifier, scope: WindowScope(pids: [4242])))
        let scanner = claimedScanner(ScopeClaims(folder: paths.instancesFolder))
        let (changes, change) = AsyncStream.makeStream(of: Void.self)
        var changed = changes.makeAsyncIterator()
        scanner.watchClaims { _ in change.yield() }
        await scanDesktop(scanner)
        #expect(!scanner.keeps(4242))

        kill(owner.processIdentifier, SIGKILL)
        await changed.next()
        #expect(FileManager.default.fileExists(atPath: paths.scopeFile.path))
        await scanDesktop(scanner)
        #expect(scanner.desktop.windows.map(\.pid) == [4242])
        #expect(scanner.keeps(4242))
    }

    func handles(to folder: URL) -> Int {
        guard let path = realpath(folder.path, nil) else { return 0 }
        defer { free(path) }
        return (0..<getdtablesize()).filter { handle in
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            return fcntl(handle, F_GETPATH, &buffer) == 0 && strcmp(buffer, path) == 0
        }.count
    }

    @Test func aManagerThatWatchesClaimsIsReleasedAndStopsItsWatches() throws {
        let paths = try #require(InstancePaths(id: "a", home: folder))
        try paths.writeClaim(ScopeClaim(owner: getpid(), scope: WindowScope(pids: [4242])))
        weak var released: WindowManager?
        weak var releasedClaims: ScopeClaims?
        do {
            let claims = ScopeClaims(folder: paths.instancesFolder)
            let manager = WindowManager(config: Config(), scanner: claimedScanner(claims))
            manager.watchClaims()
            #expect(handles(to: paths.instancesFolder) == 1)
            released = manager
            releasedClaims = claims
        }
        #expect(released == nil)
        #expect(releasedClaims == nil)
        let deadline = Date().addingTimeInterval(2)
        while handles(to: paths.instancesFolder) > 0 && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        #expect(handles(to: paths.instancesFolder) == 0)
    }

    @Test func aFolderChangeWithoutAClaimChangeStartsNoScan() async throws {
        let paths = try #require(InstancePaths(id: "plain", home: folder))
        let claims = ScopeClaims(folder: paths.instancesFolder, alive: { _ in true })
        let (changes, change) = AsyncStream.makeStream(of: Set<pid_t>.self)
        var changed = changes.makeAsyncIterator()
        claims.watch { change.yield($0) }
        defer { claims.stop() }
        try FileManager.default.createDirectory(at: paths.configFolder, withIntermediateDirectories: true)
        try Data("1".utf8).write(to: paths.pidFile, options: .atomic)
        claims.folderChanged()
        try paths.writeClaim(ScopeClaim(owner: 1, scope: WindowScope(pids: [10])))
        claims.folderChanged()
        #expect(await changed.next() == [10])
        try paths.writeClaim(ScopeClaim(owner: 1, scope: WindowScope(pids: [10, 11])))
        claims.folderChanged()
        #expect(await changed.next() == [11])
    }

    @Test func aClaimOfAProcessThatIsNoAppStartsNoRefreshButAHeldOrRunningAppDoes() throws {
        let manager = WindowManager(config: Config(), scanner: WindowScanner(readDesktop: { _ in
            WindowServerObservation()
        }, readApplications: { [] }))
        manager.claimsChanged([999_999])
        #expect(manager.refreshWork == nil)
        manager.observing[4242] = UUID()
        manager.claimsChanged([999_999, 4242])
        #expect(manager.refreshWork != nil)
        manager.refreshWork = nil
        let app = try #require(NSWorkspace.shared.runningApplications.first)
        manager.claimsChanged([app.processIdentifier])
        #expect(manager.refreshWork != nil)
    }
}
