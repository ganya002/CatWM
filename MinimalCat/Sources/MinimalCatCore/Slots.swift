/// Numbers 1 to 9 for windows. A window keeps its number until it closes, so the numbers never shuffle.
public struct Slots: Sendable {
    public private(set) var numbers: [WindowID: Int] = [:]
    public init() {}

    public mutating func update(_ windows: [WindowInfo]) {
        let present = Set(windows.map(\.id))
        numbers = numbers.filter { present.contains($0.key) }
        for window in windows where numbers[window.id] == nil {
            let taken = Set(numbers.values)
            guard let free = (1...9).first(where: { !taken.contains($0) }) else { return }
            numbers[window.id] = free
        }
    }

    public func window(_ number: Int) -> WindowID? { numbers.first { $0.value == number }?.key }
}

/// The focus order, so a tap of the cat key goes back to the last window.
public struct Recents: Sendable {
    public private(set) var order: [WindowID] = []
    public init() {}

    public mutating func focused(_ window: WindowID) {
        order.removeAll { $0 == window }
        order.insert(window, at: 0)
        if order.count > 50 { order.removeLast() }
    }

    public func previous(current: WindowID?, among present: Set<WindowID>) -> WindowID? {
        order.first { $0 != current && present.contains($0) }
    }
}
