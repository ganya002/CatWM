/// Everything the cat key can do. The menu bar shows the same list, so each one also works without a held key.
public enum Command: Hashable, Sendable {
    case place(Place)
    case focus(Side)
    case jump(Int)
    case undo, redo
    case find
    case cancel

    public enum Key: Hashable, Sendable {
        /// A key that has the same position on every layout.
        case code(UInt16)
        /// A key found by the character it types on the current layout.
        case character(Character)
    }

    public struct Binding: Sendable {
        public let key: Key
        public let label: String
        public let command: Command
    }

    public static let bindings: [Binding] = [
        Binding(key: .code(123), label: "←", command: .place(.left)),
        Binding(key: .code(124), label: "→", command: .place(.right)),
        Binding(key: .code(126), label: "↑", command: .place(.top)),
        Binding(key: .code(125), label: "↓", command: .place(.bottom)),
        Binding(key: .code(36), label: "↩", command: .place(.big)),
        Binding(key: .character(","), label: ",", command: .focus(.left)),
        Binding(key: .character("."), label: ".", command: .focus(.right)),
        Binding(key: .character("z"), label: "Z", command: .undo),
        Binding(key: .character("y"), label: "Y", command: .redo),
        Binding(key: .code(49), label: "Space", command: .find),
        Binding(key: .code(53), label: "Esc", command: .cancel)
    ] + zip([18, 19, 20, 21, 23, 22, 26, 28, 25] as [UInt16], 1...9).map { code, number in
        Binding(key: .code(code), label: "\(number)", command: .jump(number))
    }

    public var title: String {
        switch self {
        case .place(.left): "Move Left"
        case .place(.right): "Move Right"
        case .place(.top): "Move Up"
        case .place(.bottom): "Move Down"
        case .place(.big): "Make Big"
        case .focus(.left): "Window on the Left"
        case .focus(.right): "Window on the Right"
        case .jump(let number): "Window \(number)"
        case .undo: "Undo"
        case .redo: "Redo"
        case .find: "Find a Window…"
        case .cancel: "Cancel"
        }
    }

    public var binding: Binding? { Self.bindings.first { $0.command == self } }
}
