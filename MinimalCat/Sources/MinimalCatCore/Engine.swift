import CoreGraphics
import Foundation

/// What the Mac can do for the engine. The app uses Accessibility, the tests use a fake.
@MainActor
public protocol WindowSystem: AnyObject {
    func displays() -> [Display]
    /// Standard windows on the current Desktop, front to back.
    func windows() -> [WindowInfo]
    func focusedWindow() -> WindowID?
    func apply(_ moves: [Move])
    func focus(_ window: WindowID)
}

public enum Effect: Equatable, Sendable {
    case none
    /// `visible` is false when the result is already on screen. Then only VoiceOver speaks it.
    case notice(String, visible: Bool)
    case openFind
    case cancel
}

@MainActor
public final class Engine {
    public let system: WindowSystem
    public private(set) var history = History()
    public private(set) var memory: DisplayMemory
    public private(set) var slots = Slots()
    public private(set) var recents = Recents()
    private var beforeBig: [WindowID: CGRect] = [:]

    public init(system: WindowSystem, memory: DisplayMemory = DisplayMemory()) {
        self.system = system
        self.memory = memory
    }

    /// The current windows, with each one's number kept up to date.
    @discardableResult
    public func windows() -> [WindowInfo] {
        let windows = system.windows()
        slots.update(windows)
        return windows
    }

    public func perform(_ command: Command, cause: Cause = .key) -> Effect {
        switch command {
        case .place(let place): return move(to: place, cause: cause)
        case .focus(let side):
            let all = windows()
            guard let current = focused(in: all),
                  let target = Geometry.window(beside: current.frame, toward: side,
                                               among: all.filter { $0.id != current.id }) else { return .none }
            system.focus(target.id)
            return .notice(target.name, visible: false)
        case .jump(let number):
            let all = windows()
            guard let id = slots.window(number), let target = all.first(where: { $0.id == id }) else {
                return .notice("No window \(number)", visible: true)
            }
            system.focus(id)
            return .notice(target.name, visible: false)
        case .undo: return replay(history.undo(on: DisplaySet(system.displays())), verb: "Undid")
        case .redo: return replay(history.redo(on: DisplaySet(system.displays())), verb: "Redid")
        case .find: return .openFind
        case .cancel: return .cancel
        }
    }

    public func previousWindow() -> Effect {
        let all = windows()
        guard let id = recents.previous(current: system.focusedWindow(), among: Set(all.map(\.id))),
              let target = all.first(where: { $0.id == id }) else { return .none }
        system.focus(id)
        return .notice(target.name, visible: false)
    }

    public func focused(_ window: WindowID) { recents.focused(window) }

    public func windowClosed(_ window: WindowID) {
        history.forget(window)
        beforeBig[window] = nil
    }

    public func saveLayout() {
        memory.save(windows(), on: system.displays())
    }

    /// Puts windows back where they were the last time these monitors were connected.
    public func restoreLayout() -> Effect {
        let displays = system.displays()
        let moves = memory.restore(windows(), on: displays)
        guard !moves.isEmpty else { return .none }
        let step = Step(label: "Put Windows Back", cause: .restore, displays: DisplaySet(displays), moves: moves)
        apply(step.moves, on: displays)
        history.record(step)
        let count = moves.count == 1 ? "1 window" : "\(moves.count) windows"
        return .notice("Put \(count) back · \(Command.catKey) Z undoes", visible: true)
    }

    private func move(to place: Place, cause: Cause) -> Effect {
        let all = windows(), displays = system.displays()
        guard let window = focused(in: all),
              let display = Geometry.display(containing: window.frame, in: displays) else {
            return .notice("No window to move", visible: true)
        }
        let current = Geometry.place(of: window.frame, on: display)
        let target: CGRect
        var label = Command.place(place).title
        switch (place, current) {
        case (.big, _) where current == .big && beforeBig[window.id] != nil:
            target = beforeBig.removeValue(forKey: window.id) ?? window.frame
            label = "Put Back"
        case (.big, _):
            beforeBig[window.id] = window.frame
            target = Geometry.frame(for: .big, on: display)
        case (.left, _) where current == .left, (.right, _) where current == .right:
            let side: Side = place == .left ? .left : .right
            guard let next = Geometry.neighbour(of: display, toward: side, in: displays) else { return .none }
            target = Geometry.frame(for: side == .left ? .right : .left, on: next)
        default:
            target = Geometry.frame(for: place, on: display)
        }
        guard !Geometry.approxEqual(target, window.frame, tolerance: 1) else { return .none }
        let step = Step(label: label, cause: cause, displays: DisplaySet(displays),
                        moves: [Move(window: window.id, start: window.frame, end: target)])
        apply(step.moves, on: displays)
        history.record(step)
        return .notice("\(label) · \(window.app)", visible: false)
    }

    private func replay(_ pop: History.Pop, verb: String) -> Effect {
        switch pop {
        case .empty: return .notice("Nothing to \(verb == "Undid" ? "undo" : "redo")", visible: true)
        case .otherDisplays: return .notice("That change was on other monitors", visible: true)
        case .step(let step):
            let present = Set(windows().map(\.id))
            let moves = step.moves.filter { present.contains($0.window) }
            guard !moves.isEmpty else { return .notice("That window is not on screen", visible: true) }
            let displays = system.displays()
            for move in moves {
                let big = Geometry.display(containing: move.end, in: displays)
                    .map { Geometry.place(of: move.end, on: $0) == .big } ?? false
                beforeBig[move.window] = big ? move.start : nil
            }
            apply(moves, on: displays)
            return .notice("\(verb) \(step.label)", visible: true)
        }
    }

    private func apply(_ moves: [Move], on displays: [Display]) {
        system.apply(moves)
        let targets = Dictionary(moves.map { ($0.window, $0.end) }, uniquingKeysWith: { _, last in last })
        memory.save(windows().map { window in
            var moved = window
            moved.frame = targets[window.id] ?? window.frame
            return moved
        }, on: displays)
    }

    private func focused(in windows: [WindowInfo]) -> WindowInfo? {
        guard let id = system.focusedWindow() else { return nil }
        return windows.first { $0.id == id }
    }
}
