/// Numbers 1 to 9 for windows. A window keeps its number while it is on another Desktop, so the numbers of a
/// Desktop never shuffle. A number is unique only among the windows on screen. When two claim one, the front
/// window keeps it.
public struct Slots: Sendable {
    static let remembered = 300
    public private(set) var numbers: [WindowID: Int] = [:]
    private var onScreen: [WindowID] = []
    public init() {}

    /// `windows` are the windows on screen, front to back.
    public mutating func update(_ windows: [WindowInfo]) {
        onScreen = windows.map(\.id)
        var taken: Set<Int> = []
        for id in onScreen {
            guard let number = numbers[id] else { continue }
            if taken.insert(number).inserted == false { numbers[id] = nil }
        }
        for id in onScreen where numbers[id] == nil {
            guard let free = (1...9).first(where: { !taken.contains($0) }) else { break }
            numbers[id] = free
            taken.insert(free)
        }
        if numbers.count > Self.remembered {
            let present = Set(onScreen)
            numbers = numbers.filter { present.contains($0.key) }
        }
    }

    /// The window on screen with this number.
    public func window(_ number: Int) -> WindowID? { onScreen.first { numbers[$0] == number } }

    public func number(of window: WindowID) -> Int? { onScreen.contains(window) ? numbers[window] : nil }
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
