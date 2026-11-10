import AppKit

package struct DividerState {
    package struct DividerDrag {
        package let screen: String
        package let startRatio: CGFloat
        package var position: CGFloat?
    }

    package var dividerDrag: DividerDrag?
    package var ratioChange: (screen: String, until: Date)?
}

extension WindowManager {
    package func splitDivider(on screen: Screen) -> SplitDivider? {
        guard config.splitHandle, isStarted, tilingEnabled, !closeAndSort.sortSession else { return nil }
        let screenState = state(for: screen)
        guard screenState.zoomed == nil else { return nil }
        let ids = splitIDs(on: screen)
        let slots = ids.compactMap(splitSlot)
        guard slots.count == ids.count,
              let divider = SplitDivider(layout: screenState.layout, slots: slots, mainCount: screenState.mainCount,
                                         in: usableRect(screen)),
              isOnHomeSpace(screen) else { return nil }
        return divider
    }

    package func beginDividerDrag(on screen: Screen) {
        dividerState.dividerDrag = .init(screen: screen.uuid, startRatio: state(for: screen).ratio)
    }

    package func moveDivider(on screen: Screen, to position: CGFloat) {
        guard var drag = dividerState.dividerDrag, drag.screen == screen.uuid,
              let divider = splitDivider(on: screen) else { return }
        drag.position = position
        dividerState.dividerDrag = drag
        let screenState = state(for: screen), ids = splitIDs(on: screen)
        let wanted = divider.ratio(at: position, in: usableRect(screen), gap: windowGap(count: ids.count))
        let ratio = allowedRatio(from: drag.startRatio, to: wanted, ids: ids, on: screen, screenState)
        guard abs(ratio - screenState.ratio) > 0.0005 else { return }
        screenState.ratio = ratio
        corrections = [:]
        refresh()
    }

    package func endDividerDrag() {
        guard dividerState.dividerDrag != nil else { return }
        dividerState.dividerDrag = nil
        animator.endFollow()
        corrections = [:]
        refresh()
    }

    private func allowedRatio(
        from start: CGFloat, to wanted: CGFloat, ids: [CGWindowID], on screen: Screen, _ screenState: ScreenState
    ) -> CGFloat {
        func fits(_ ratio: CGFloat) -> Bool {
            windowRefusingRatio(ratio, from: start, ids: ids, on: screen, screenState) == nil
        }
        guard !fits(wanted) else { return wanted }
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if fits(start + (wanted - start) * mid) { low = mid } else { high = mid }
        }
        return start + (wanted - start) * low
    }

    package func swapSides(on screen: Screen) {
        let screenState = state(for: screen), ids = splitIDs(on: screen)
        let mains = SplitDivider.mains(screenState.layout, mainCount: screenState.mainCount, count: ids.count)
        guard ids.count > mains, screenState.layout.ratioAxis != nil else { return }
        if let mirrored = screenState.layout.mirrored {
            screenState.layout = mirrored
        } else {
            swapOrder(ids[0], ids[mains])
        }
        corrections = [:]
        refresh()
        surface.splitSwapped(on: screen.uuid)
    }

    package func swapSides() {
        guard let screen = currentScreen() else { return }
        swapSides(on: screen)
    }

    private func splitSlot(_ id: CGWindowID) -> CGRect? {
        guard corrections[id] != nil, !animator.isBusy(id), let window = windows[id],
              !window.cachedFrame.isNull else { return targets[id] }
        return window.cachedFrame
    }

    package func splitIDs(on screen: Screen) -> [CGWindowID] {
        tiled(on: screen).filter { !nativeMoves.isMoving($0) }
    }
}
