import AppKit

enum DesktopLifecycle {
    struct Creation {
        let space: UInt64
        let snapshot: Spaces.Snapshot
    }

    @MainActor static func create(on screen: Screen, snapshot supplied: Spaces.Snapshot? = nil,
                                  before successor: UInt64? = nil) async throws -> Creation {
        guard DesktopUI.isSettled(screen),
              let before = (supplied ?? Spaces.snapshot())?.list(display: screen.uuid) else {
            throw DesktopTransitionError.check("Finish the current macOS Desktop action first")
        }
        let index = successor.flatMap { before.ids.firstIndex(of: $0) } ?? before.ids.count
        let started = ProcessInfo.processInfo.systemUptime
        guard let space = DesktopBridge.create() else {
            throw DesktopTransitionError.check("macOS could not create a Desktop")
        }
        do {
            let snapshot = try await place(space, on: screen, index: index)
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            Log.info("native workspaces: created Desktop \(space) on \(screen.uuid) in \(elapsed) ms")
            DesktopMenuBar.created(space)
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

    @MainActor static func remove(_ space: UInt64, on screen: Screen) async throws {
        guard let info = Spaces.list(display: screen.uuid), info.desktops.count > 1,
              let index = info.ids.firstIndex(of: space), info.desktops.contains(index),
              Spaces.current(display: screen.uuid) != space, DesktopUI.isSettled(screen) else {
            throw DesktopTransitionError.check("This Desktop cannot be removed right now")
        }
        let occupied = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements]).contains {
            Spaces.of(window: $0.id) == [space]
        }
        guard !occupied else {
            throw DesktopTransitionError.check("Move all windows out of the Desktop before removing it")
        }
        let started = ProcessInfo.processInfo.systemUptime
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
