import CoreGraphics

let modifiers: [String: (code: CGKeyCode, flag: CGEventFlags)] = [
    "control": (59, .maskControl), "option": (58, .maskAlternate), "shift": (56, .maskShift),
    "command": (55, .maskCommand)
]
let source = CGEventSource(stateID: .hidSystemState)

func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
        fatalError("smoke-keys: can't make an event for key \(code)")
    }
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

for stroke in CommandLine.arguments.dropFirst() {
    let parts = stroke.split(separator: "+").map(String.init)
    guard let code = CGKeyCode(parts[0]) else { fatalError("smoke-keys: `\(parts[0])` is not a key code") }
    let held = parts.dropFirst().map { name in
        guard let modifier = modifiers[name] else { fatalError("smoke-keys: unknown modifier `\(name)`") }
        return modifier
    }
    var flags: CGEventFlags = []
    for modifier in held {
        flags.insert(modifier.flag)
        post(modifier.code, down: true, flags: flags)
    }
    post(code, down: true, flags: flags)
    post(code, down: false, flags: flags)
    for modifier in held.reversed() {
        flags.remove(modifier.flag)
        post(modifier.code, down: false, flags: flags)
    }
}
