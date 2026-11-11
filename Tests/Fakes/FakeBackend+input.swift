import AppKit
import CatWMKit

extension FakeBackend {
    package var currentDesktop: Int { state.withLockUnchecked { state in state.desktop } }

    package var desktopSwitches: [Int] { state.withLockUnchecked { state in state.desktopSwitches } }

    package func desktop(of id: CGWindowID) -> Int? { state.withLockUnchecked { state in state.desktopOf[id] } }

    package var inputs: [Input] { state.withLockUnchecked { state in state.inputLog } }

    package func setDesktops(_ count: Int) { state.withLockUnchecked { state in state.desktopCount = count } }

    package func setPointer(_ point: CGPoint) { state.withLockUnchecked { state in state.pointer = point } }
}

extension FakeBackend {
    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124

    @MainActor package func pointerLocation() -> CGPoint { state.withLockUnchecked { state in state.pointer } }

    @MainActor package func warpPointer(to point: CGPoint) {
        state.withLockUnchecked { state in
            state.inputLog.append(.warp(point))
            state.pointer = point
        }
    }

    @MainActor package func post(keyCode: UInt16, flags: CGEventFlags, style _: Hotkeys.PostStyle) {
        state.withLockUnchecked { state in
            state.inputLog.append(.key(keyCode, flags: flags.rawValue))
            let step = keyCode == Self.rightArrow ? 1 : keyCode == Self.leftArrow ? -1 : 0
            let next = min(max(state.desktop + step, 1), state.desktopCount)
            guard step != 0, next != state.desktop else { return }
            state.desktop = next
            state.desktopSwitches.append(next)
            if let held = state.held { state.desktopOf[held.id] = next }
        }
    }

    @MainActor package func postMouse(_ type: CGEventType, at point: CGPoint) {
        state.withLockUnchecked { state in
            state.inputLog.append(.mouse(type.rawValue, point))
            state.pointer = point
            switch type {
            case .leftMouseDown:
                let top = state.stacking.compactMap { state.windowList[$0] }.first { $0.frame.contains(point) }
                state.held = top.map { Held(id: $0.id, start: point, current: point) }
            case .leftMouseDragged:
                state.held?.current = point
            case .leftMouseUp:
                state.held = nil
            default:
                break
            }
        }
    }

    @MainActor package func serverFrame(of id: CGWindowID) -> CGRect? {
        state.withLockUnchecked { state in
            guard let frame = state.windowList[id]?.frame else { return nil }
            guard let held = state.held, held.id == id else { return frame }
            return frame.offsetBy(dx: held.current.x - held.start.x, dy: held.current.y - held.start.y)
        }
    }

    @MainActor package func spaceList(display _: String) -> Spaces.DisplaySpaces? {
        state.withLockUnchecked { state in
            let ids = (1...state.desktopCount).map { UInt64($0) }
            return Spaces.DisplaySpaces(ids: ids, desktops: Array(ids.indices), current: state.desktop - 1)
        }
    }

    @MainActor package func desktopShortcut(_: Int) -> SystemShortcut.Combo? { nil }

    @MainActor package func stepShortcut(right: Bool) -> SystemShortcut.Combo? {
        SystemShortcut.Combo(keyCode: right ? Self.rightArrow : Self.leftArrow, flags: [.maskControl, .maskSecondaryFn])
    }
}
