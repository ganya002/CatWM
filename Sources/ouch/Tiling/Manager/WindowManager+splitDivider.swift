import AppKit

extension WindowManager {
    func splitDivider(on screen: Screen) -> SplitDivider? {
        guard config.splitHandle, isStarted, tilingEnabled, !sortSession else { return nil }
        let screenState = state(for: screen)
        guard screenState.zoomed == nil else { return nil }
        let ids = splitIDs(on: screen)
        let slots = ids.compactMap { targets[$0] }
        guard slots.count == ids.count,
              let divider = SplitDivider(layout: screenState.layout, slots: slots, mainCount: screenState.mainCount,
                                         in: usableRect(screen)),
              isOnHomeSpace(screen) else { return nil }
        return divider
    }

    func beginDividerDrag(on screen: Screen) {
        dividerDrag = DividerDrag(screen: screen.uuid, startRatio: state(for: screen).ratio)
    }

    func moveDivider(on screen: Screen, to position: CGFloat) {
        guard var drag = dividerDrag, drag.screen == screen.uuid, let divider = splitDivider(on: screen) else { return }
        drag.position = position
        dividerDrag = drag
        let screenState = state(for: screen), ids = splitIDs(on: screen)
        let wanted = divider.ratio(at: position, in: usableRect(screen), gap: windowGap(count: ids.count))
        let ratio = allowedRatio(from: drag.startRatio, to: wanted, ids: ids, on: screen, screenState)
        guard abs(ratio - screenState.ratio) > 0.0005 else { return }
        screenState.ratio = ratio
        corrections = [:]
        refresh()
    }

    func endDividerDrag() {
        guard dividerDrag != nil else { return }
        dividerDrag = nil
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

    func swapSides(on screen: Screen) {
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
        SplitHandle.shared.confirmSwap(on: screen.uuid)
    }

    func swapSides() {
        guard let screen = currentScreen() else { return }
        swapSides(on: screen)
    }

    private func splitIDs(on screen: Screen) -> [CGWindowID] {
        tiled(on: screen).filter { !workspaceMoves.contains($0) }
    }
}
