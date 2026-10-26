import AppKit

extension WindowManager {
    func layoutTargets(_ ids: [CGWindowID], _ screenState: ScreenState, on screen: Screen) -> [CGWindowID: CGRect]? {
        let rect = usableRect(screen), gap = windowGap(count: ids.count)
        syncStrip(screenState, ids)
        for (index, column) in screenState.strip.columns.enumerated() {
            let widest = column.ids.compactMap { minSizes[$0]?.width }.max() ?? 0
            let needed = (widest + gap) / (rect.width + gap)
            if needed > column.width {
                screenState.strip.columns[index].width = min(Strip.widthRange.upperBound, needed)
            }
            guard column.ids.count > 1 else { continue }
            screenState.strip.columns[index].heights = Strip.fitted(
                column.heights, minimums: column.ids.map { (minSizes[$0]?.height ?? 0) + gap }, in: rect.height + gap)
        }
        let focus = model.mostRecent(of: screenState.strip.ids)
        screenState.strip.reveal(focus, in: rect, gap: gap, scroll: config.columnScroll,
                                 centerSingle: config.centerSingleColumn)
        let virtual = screenState.strip.frames(in: rect, gap: gap)
        let screens = backend.screens()
        var out: [CGWindowID: CGRect] = [:]
        for (id, frame) in virtual {
            stripFrames[id] = frame
            out[id] = id == screenState.zoomed ? rect.pixelAligned : stripPlacement(frame, on: screen, screens)
        }
        return out
    }

    private func syncStrip(_ screenState: ScreenState, _ ids: [CGWindowID]) {
        let tiled = Set(ids)
        var placed: Set<CGWindowID> = []
        for old in screenState.strip.ids where !tiled.contains(old) {
            guard let member = tabs.group(of: old)?.members.first(where: tiled.contains),
                  placed.insert(member).inserted else { continue }
            screenState.strip.remove(member)
            screenState.strip.replace(old, with: member)
        }
        screenState.strip.sync(ids, focus: model.mostRecent(of: screenState.strip.ids), width: config.columnWidth)
    }

    func stripPlacement(_ frame: CGRect, on screen: Screen, _ screens: [Screen]) -> CGRect {
        let overlap = frame.intersection(screen.frame)
        if !overlap.isNull, overlap.width >= 1, !crossesOtherScreen(frame, of: screen, screens) { return frame }
        return CGRect(origin: parkingSpot(size: frame.size, on: screen, screens), size: frame.size)
    }

    func crossesOtherScreen(_ frame: CGRect, of screen: Screen, _ screens: [Screen]) -> Bool {
        screens.contains { $0.uuid != screen.uuid && $0.frame.intersects(frame) }
    }

    func stripExit(from current: CGRect, on screen: Screen) -> CGRect {
        let x = current.midX >= screen.frame.midX ? screen.frame.maxX - 1 : screen.frame.minX - current.width + 1
        return CGRect(x: x, y: current.minY, width: current.width, height: current.height)
    }

    func stripEntry(to target: CGRect, on screen: Screen) -> CGRect {
        let x = target.midX >= screen.frame.midX ? screen.frame.maxX - 1 : screen.frame.minX - target.width + 1
        return CGRect(x: x, y: target.minY, width: target.width, height: target.height)
    }

    func revealInStrip(_ id: CGWindowID) {
        guard let workspace = workspaceOf[id], isShown(workspace), let screenState = states[workspace],
              let window = windows[id], !window.isFloating, let screen = screen(of: window),
              screenState.strip.column(of: id) != nil else { return }
        var strip = screenState.strip
        let ids = tiled(on: screen)
        strip.reveal(id, in: usableRect(screen), gap: windowGap(count: ids.count), scroll: config.columnScroll,
                     centerSingle: config.centerSingleColumn)
        if strip.offset != screenState.strip.offset { refresh() }
    }

    struct StripContext {
        let window: Window
        let screen: Screen
        let state: ScreenState
    }

    func stripContext() -> StripContext? {
        guard let window = focusedWindow(), !window.isFloating, let screen = screen(of: window) else { return nil }
        let screenState = state(for: screen)
        guard screenState.strip.column(of: window.id) != nil else { return nil }
        return StripContext(window: window, screen: screen, state: screenState)
    }

    func editStrip(_ change: (inout Strip, CGWindowID) -> Bool) {
        guard let context = stripContext(), change(&context.state.strip, context.window.id) else { return }
        corrections = [:]
        refresh()
        focus(context.window, warp: false)
    }

    func columnWidthCommand(_ arg: String) {
        let text = arg.lowercased().trimmingCharacters(in: .whitespaces)
        editStrip { strip, id in
            switch text {
            case "", "cycle", "next": strip.cycleWidth(of: id, presets: config.columnWidths)
            case "max", "maximize", "full": strip.setWidth(of: id) { $0 >= 1 ? self.config.columnWidth : 1 }
            default:
                guard let value = Double(text.replacingOccurrences(of: "+", with: "")) else { return false }
                let amount = CGFloat(abs(value) >= 1 ? value / 100 : value)
                let relative = text.hasPrefix("+") || text.hasPrefix("-")
                strip.setWidth(of: id) { relative ? $0 + amount : amount }
            }
            return true
        }
    }

    func windowHeightCommand(_ arg: String) {
        guard let value = Double(arg.replacingOccurrences(of: "+", with: "")) else { return }
        editStrip { strip, id in
            strip.setHeight(of: id, by: CGFloat(abs(value) >= 1 ? value / 100 : value))
            return true
        }
    }

    func centerColumn() {
        guard let context = stripContext() else { return }
        let screen = context.screen
        context.state.strip.reveal(context.window.id, in: usableRect(screen),
                                   gap: windowGap(count: tiled(on: screen).count),
                                   scroll: .center, centerSingle: config.centerSingleColumn)
        refresh()
    }

    func consumeOrExpel(_ direction: Direction) {
        guard direction == .left || direction == .right else { return }
        editStrip { strip, id in strip.consumeOrExpel(id, by: direction == .left ? -1 : 1) }
    }

    func moveInStrip(_ window: Window, _ direction: Direction) -> Bool {
        guard let context = stripContext(), context.window.id == window.id else { return false }
        switch direction {
        case .left, .right: return context.state.strip.moveColumn(of: window.id, by: direction == .left ? -1 : 1)
        case .upward, .down: return context.state.strip.moveInColumn(window.id, by: direction == .upward ? -1 : 1)
        }
    }

    func toggleColumnTabs() {
        guard let context = stripContext(),
              let index = context.state.strip.column(of: context.window.id) else { return }
        let window = context.window, screenState = context.state
        if let group = tabs.group(of: window.id) {
            let members = group.members.filter { $0 != window.id }
            for member in members { model.leaveTab(member) }
            screenState.strip.columns[index].ids += members
            screenState.strip.columns[index].heights += members.map { _ in 1 }
        } else {
            let others = screenState.strip.columns[index].ids.filter { $0 != window.id }
            guard !others.isEmpty else { return }
            for other in others { model.joinTab(other, onto: window.id) }
        }
        corrections = [:]
        refresh()
        focus(window, warp: false)
    }

    func resizeColumn(_ window: Window, on screen: Screen) {
        let screenState = state(for: screen)
        let frame = window.cachedFrame
        guard !frame.isNull, let index = screenState.strip.column(of: window.id) else { return }
        let rect = usableRect(screen), gap = windowGap(count: tiled(on: screen).count)
        let column = screenState.strip.columns[index]
        let width = (frame.width + gap) / (rect.width + gap)
        screenState.strip.setWidth(of: window.id) { _ in width }
        if column.ids.count > 1, let row = column.ids.firstIndex(of: window.id) {
            let share = (frame.height + gap) / (rect.height + gap)
            let current = column.heights[row] / column.heights.reduce(0, +)
            screenState.strip.setHeight(of: window.id, by: share - current)
        }
    }

    func stripLine(_ screenState: ScreenState) -> String {
        screenState.strip.columns.map { column in
            "\(String(format: "%.3f", Double(column.width)))/" + column.ids.map(String.init).joined(separator: ",")
        }.joined(separator: " ")
    }

    func loadStrip(_ line: String) -> Strip {
        var strip = Strip()
        for part in line.split(separator: " ") {
            let pieces = part.split(separator: "/", maxSplits: 1)
            guard pieces.count == 2, let width = Double(pieces[0]) else { continue }
            let ids = pieces[1].split(separator: ",").compactMap { CGWindowID($0) }
            guard !ids.isEmpty else { continue }
            strip.columns.append(.init(ids, width: min(1, max(0.1, CGFloat(width)))))
        }
        return strip
    }
}
