import AppKit

struct KeyBinding: Equatable {
    let keyCode: UInt16
    let mods: CGEventFlags
    let dispatcher: String
    let arg: String
    var submap = ""
    var repeats = false
}

struct BindInterpretation {
    enum Failure: Error {
        case modifier(String)
        case range(String)
        case key(String)

        var message: String {
            switch self {
            case .modifier(let name): return "unknown modifier `\(name)`"
            case .range(let message): return message
            case .key(let name): return "unknown key `\(name)`"
            }
        }
    }

    let flags: NSEvent.ModifierFlags
    let bindings: [KeyBinding]

    static func read(_ row: BindRow, mods: String? = nil) -> Result<Self, Failure> {
        let modifiers = mods ?? row.mods
        guard let flags = ConfigText.flags(modifiers) else {
            let unknown = modifiers.uppercased().split(whereSeparator: { " _+".contains($0) })
                .first { ConfigText.flags(String($0)) == nil }
            return .failure(.modifier(unknown.map(String.init) ?? modifiers))
        }
        let pairs: [(key: String, arg: String)]
        switch BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) {
        case .success(let found): pairs = found
        case .failure(let failure): return .failure(.range(failure.message))
        }
        var bindings: [KeyBinding] = []
        for (key, arg) in pairs {
            guard let code = keyCodes[key.lowercased()] else { return .failure(.key(key)) }
            bindings.append(KeyBinding(keyCode: code, mods: CGEventFlags(rawValue: UInt64(flags.rawValue)),
                                       dispatcher: row.dispatcher, arg: arg, submap: row.submap,
                                       repeats: ["binde", "bindel", "bindle"].contains(row.kind)))
        }
        return .success(Self(flags: flags, bindings: bindings))
    }
}

enum SpecialKey {
    static let mouseUp: UInt16 = 0x1000, mouseDown: UInt16 = 0x1001
    static let mouseLeft: UInt16 = 0x1002, mouseRight: UInt16 = 0x1003
    static let swipeLeft: UInt16 = 0x1010, swipeRight: UInt16 = 0x1011
    static let swipeUp: UInt16 = 0x1012, swipeDown: UInt16 = 0x1013
    static func isScroll(_ code: UInt16) -> Bool { (0x1000...0x1003).contains(code) }
    static func isSwipe(_ code: UInt16) -> Bool { (0x1010...0x1013).contains(code) }
}

let keyCodes: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "equal": 24, "=": 24, "9": 25, "7": 26, "minus": 27, "-": 27, "8": 28, "0": 29,
    "bracketright": 30, "]": 30, "o": 31, "u": 32, "bracketleft": 33, "[": 33, "i": 34, "p": 35,
    "return": 36, "enter": 36, "l": 37, "j": 38, "apostrophe": 39, "quote": 39, "'": 39, "k": 40,
    "semicolon": 41, ";": 41, "backslash": 42, "\\": 42, "comma": 43, "n": 45, "m": 46,
    "slash": 44, "/": 44, "period": 47, ".": 47, "tab": 48, "space": 49, "grave": 50, "`": 50,
    "backspace": 51, "escape": 53, "esc": 53, "capslock": 57, "caps": 57, "caps_lock": 57,
    "section": 10, "yen": 93, "underscore_jis": 94, "eisu": 102, "kana": 104,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "home": 115, "pageup": 116, "prior": 116, "delete": 117, "end": 119, "pagedown": 121, "next": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "mouse_up": SpecialKey.mouseUp, "mouse_down": SpecialKey.mouseDown,
    "mouse_left": SpecialKey.mouseLeft, "mouse_right": SpecialKey.mouseRight,
    "swipe_left": SpecialKey.swipeLeft, "swipe_right": SpecialKey.swipeRight,
    "swipe_up": SpecialKey.swipeUp, "swipe_down": SpecialKey.swipeDown
]
