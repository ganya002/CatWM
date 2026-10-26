import Foundation

/// The one held key. A tap goes back, a hold shows everything, and the key plus one more key acts.
public struct CatKey: Sendable {
    public static let tapLimit: TimeInterval = 0.25

    public enum Event: Equatable, Sendable {
        case press(time: TimeInterval)
        case release(time: TimeInterval)
        case key(UInt16)
        case tick(time: TimeInterval)
    }

    public enum Output: Equatable, Sendable {
        case previousWindow
        case showOverlay
        case hideOverlay
        case act(UInt16)
    }

    enum State: Equatable {
        case idle
        case pressed(since: TimeInterval)
        case held(showing: Bool)
    }

    private(set) var state = State.idle
    public init() {}

    public var isHeld: Bool { state != .idle }

    /// Returns what to do. A `.key` while the cat key is up returns nil, so the key goes to the app.
    public mutating func handle(_ event: Event) -> [Output]? {
        switch (state, event) {
        case (.idle, .press(let time)):
            state = .pressed(since: time)
            return []
        case (.idle, .key):
            return nil
        case (.idle, _):
            return []
        case (.pressed(let since), .release(let time)):
            state = .idle
            return time - since < Self.tapLimit ? [.previousWindow] : []
        case (.pressed(let since), .tick(let time)):
            guard time - since >= Self.tapLimit else { return [] }
            state = .held(showing: true)
            return [.showOverlay]
        case (.pressed, .key(let code)):
            state = .held(showing: false)
            return [.act(code)]
        case (.held(let showing), .release):
            state = .idle
            return showing ? [.hideOverlay] : []
        case (.held, .key(let code)):
            return [.act(code)]
        case (_, .press), (.held, .tick):
            return []
        }
    }
}
