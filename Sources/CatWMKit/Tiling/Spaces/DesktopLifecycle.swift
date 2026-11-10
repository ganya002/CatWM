import AppKit

package enum DesktopLifecycle {
    package struct Creation {
        package let space: UInt64
        package let snapshot: Spaces.Snapshot
    }

    @MainActor package static func create(on screen: Screen, snapshot supplied: Spaces.Snapshot? = nil,
                                          before successor: UInt64? = nil) async throws -> Creation {
        guard let before = (supplied ?? Spaces.snapshot())?.list(display: screen.uuid) else {
            throw DesktopTransitionError.check("macOS could not read the Desktops")
        }
        let index = successor.flatMap { before.ids.firstIndex(of: $0) } ?? before.ids.count
        let started = ProcessInfo.processInfo.systemUptime
        guard let space = DesktopBridge.create() else {
            throw DesktopTransitionError.check("macOS could not create a Desktop")
        }
        let created = ProcessInfo.processInfo.systemUptime
        if let current = before.current {
            DesktopMenuBarCover.shared.begin(on: screen, source: before.ids[current], target: space)
            DesktopWallpaperCover.shared.prepare(on: screen, source: before.ids[current], target: space, fresh: true)
        }
        let covered = ProcessInfo.processInfo.systemUptime
        do {
            let snapshot = try await place(space, on: screen, index: index)
            let placed = ProcessInfo.processInfo.systemUptime
            Log.info(String(format: "native workspaces: created Desktop %llu on %@ in %.1f ms "
                + "(SkyLight %.1f ms, cover %.1f ms, placement %.1f ms)",
                space, screen.uuid, (placed - started) * 1_000, (created - started) * 1_000,
                (covered - created) * 1_000, (placed - covered) * 1_000))
            DesktopMenuBar.created(space, in: snapshot)
            return Creation(space: space, snapshot: snapshot)
        } catch {
            for host in Screen.all() where Spaces.list(display: host.uuid)?.ids.contains(space) == true {
                do { try await remove(space, on: host) } catch {
                    Log.info("native workspaces: could not remove the unused Desktop \(space): "
                        + error.localizedDescription)
                }
            }
            throw error
        }
    }

    @MainActor private static func place(_ space: UInt64, on screen: Screen,
                                         index: Int) async throws -> Spaces.Snapshot {
        func placed() -> Spaces.Snapshot? {
            guard let snapshot = Spaces.snapshot(), let info = snapshot.list(display: screen.uuid),
                  info.ids.firstIndex(of: space) == index, info.desktops.contains(index) else { return nil }
            return snapshot
        }
        if let snapshot = placed() { return snapshot }
        guard DesktopBridge.move(space, to: screen.uuid, index: Int32(index)) else {
            throw DesktopTransitionError.check("macOS could not place the Desktop on this display")
        }
        var snapshot: Spaces.Snapshot?
        let ready = await poll(1) { snapshot = placed(); return snapshot != nil }
        guard ready, let snapshot else {
            throw DesktopTransitionError.check("macOS did not create the requested Desktop")
        }
        return snapshot
    }

    @MainActor package static func remove(_ space: UInt64, on screen: Screen) async throws {
        guard let info = Spaces.list(display: screen.uuid), info.desktops.count > 1,
              let index = info.ids.firstIndex(of: space), info.desktops.contains(index),
              Spaces.current(display: screen.uuid) != space, DesktopUI.isSettled(screen) else {
            throw DesktopTransitionError.check("This Desktop cannot be removed right now")
        }
        let windows = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements])
        let memberships = WindowServerQuery.memberships(for: Set(windows.map(\.id)))
        let occupant = windows.first { memberships[$0.id] == [space] }
        if let occupant {
            let owner = NSRunningApplication(processIdentifier: occupant.pid)?.bundleIdentifier ?? "\(occupant.pid)"
            Log.info("native workspaces: window \(occupant.id) of \(owner) is on Desktop \(space)")
            throw DesktopTransitionError.occupied
        }
        let started = ProcessInfo.processInfo.systemUptime
        DesktopWallpaperCover.shared.withdraw(from: space)
        guard DesktopBridge.remove(space) else {
            throw DesktopTransitionError.check("macOS could not remove the Desktop")
        }
        let removed = await poll(1) { Spaces.list(display: screen.uuid)?.ids.contains(space) == false }
        guard removed else { throw DesktopTransitionError.check("macOS did not remove the Desktop") }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
        DesktopMenuBar.removed()
        Log.info("native workspaces: removed Desktop \(space) in \(elapsed) ms")
    }
}
