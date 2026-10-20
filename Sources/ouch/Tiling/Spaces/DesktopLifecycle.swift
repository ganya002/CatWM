import AppKit

enum DesktopLifecycle {
    @MainActor static func create(on screen: Screen) async throws -> UInt64 {
        guard !DesktopUI.isBusy(on: screen), let before = Spaces.list(display: screen.uuid) else {
            throw DesktopTransitionError.check("Finish the current macOS Desktop action first")
        }
        let original = Set(before.ids)
        guard openMissionControl() else {
            throw DesktopTransitionError.check("Cannot open Mission Control to create a Desktop")
        }
        var closed = false
        defer { if !closed { dismiss(on: screen) } }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var pressed = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !pressed, let button = spacesElement(display: screen.id, identifier: "mc.spaces.add") {
                guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                    throw DesktopTransitionError.check("macOS refused to create a Desktop")
                }
                pressed = true
            }
            if pressed, let list = Spaces.list(display: screen.uuid),
               let created = list.desktops.map({ list.ids[$0] }).first(where: { !original.contains($0) }) {
                dismiss(on: screen)
                closed = true
                try await Task.sleep(nanoseconds: 400_000_000)
                return created
            }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw DesktopTransitionError.check("macOS did not create the requested Desktop")
    }

    @MainActor static func remove(_ space: UInt64, on screen: Screen) async throws {
        guard let info = Spaces.list(display: screen.uuid), info.desktops.count > 1,
              let index = info.ids.firstIndex(of: space), info.desktops.contains(index),
              Spaces.current(display: screen.uuid) != space, !DesktopUI.isBusy(on: screen) else {
            throw DesktopTransitionError.check("This Desktop cannot be removed right now")
        }
        let occupied = CGWindowInfo.onScreen(options: [.optionAll, .excludeDesktopElements]).contains {
            Spaces.of(window: $0.id) == [space]
        }
        guard !occupied else {
            throw DesktopTransitionError.check("Move all windows out of the Desktop before removing it")
        }
        guard openMissionControl() else {
            throw DesktopTransitionError.check("Cannot open Mission Control")
        }
        defer { dismiss(on: screen) }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var pressed = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !pressed, let list = spacesElement(display: screen.id, identifier: "mc.spaces.list") {
                let children = list.elements(kAXChildrenAttribute)
                if children.indices.contains(index) {
                    pressed = AXUIElementPerformAction(children[index], "AXRemoveDesktop" as CFString) == .success
                }
            }
            if pressed, Spaces.list(display: screen.uuid)?.ids.contains(space) == false { return }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        throw DesktopTransitionError.check("macOS did not remove the Desktop")
    }

    private static func openMissionControl() -> Bool {
        typealias Notify = @convention(c) (CFString, Int32) -> Void
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else {
            return false
        }
        unsafeBitCast(pointer, to: Notify.self)("com.apple.expose.awake" as CFString, 0)
        return true
    }

    @MainActor private static func dismiss(on screen: Screen) {
        if pressCurrentDesktop(on: screen) { return }
        Task { @MainActor in
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while ProcessInfo.processInfo.systemUptime < deadline {
                if pressCurrentDesktop(on: screen) { return }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            if DesktopUI.isBusy(on: screen) {
                Log.info("native workspaces: Mission Control did not close")
            }
        }
    }

    private static func pressCurrentDesktop(on screen: Screen) -> Bool {
        guard let info = Spaces.list(display: screen.uuid), let index = info.current,
              let list = spacesElement(display: screen.id, identifier: "mc.spaces.list") else { return false }
        let children = list.elements(kAXChildrenAttribute)
        guard children.indices.contains(index) else { return false }
        return AXUIElementPerformAction(children[index], kAXPressAction as CFString) == .success
    }

    private static func spacesElement(display: CGDirectDisplayID, identifier: String) -> AXUIElement? {
        guard let monitor = DesktopUI.missionControlDisplays().first(where: {
            ($0.value("AXDisplayID") as? UInt32) == display
        }), let spaces = monitor.elements(kAXChildrenAttribute).first(where: {
            $0.string("AXIdentifier") == "mc.spaces"
        }) else { return nil }
        return spaces.elements(kAXChildrenAttribute).first { $0.string("AXIdentifier") == identifier }
    }
}
