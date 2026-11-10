import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

private struct Bind: Hashable {
    let submap: String
    let mods: UInt64
    let key: UInt16
    let dispatcher: String
    let arg: String
}

private func binds(_ text: String) -> [Bind] {
    let config = Config.parse(text)
    #expect(config.errors.isEmpty, "\(config.errors)")
    return config.bindings.map {
        Bind(submap: $0.submap, mods: $0.mods.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
                .rawValue, key: $0.keyCode, dispatcher: $0.dispatcher, arg: $0.arg)
    }
}

private func bind(_ submap: String, _ mods: CGEventFlags, _ key: String, _ dispatcher: String,
                  _ arg: String = "") -> Bind {
    Bind(submap: submap, mods: mods.rawValue, key: keyCodes[key] ?? .max, dispatcher: dispatcher, arg: arg)
}

private let controlOption: CGEventFlags = [.maskControl, .maskAlternate]

private let globalAdditions: [Bind] = [
    bind("", controlOption, "h", "movefocus", "l"),
    bind("", controlOption, "j", "movefocus", "d"),
    bind("", controlOption, "k", "movefocus", "u"),
    bind("", controlOption, "l", "movefocus", "r"),
    bind("", controlOption.union(.maskShift), "h", "movewindow", "l"),
    bind("", controlOption.union(.maskShift), "j", "movewindow", "d"),
    bind("", controlOption.union(.maskShift), "k", "movewindow", "u"),
    bind("", controlOption.union(.maskShift), "l", "movewindow", "r"),
    bind("", controlOption, "f", "fullscreen"),
    bind("", controlOption, "v", "togglefloating")
]

private let sharedWindowAdditions: [Bind] = [
    bind("window", [], "o", "sort"),
    bind("window", [], "slash", "switcher"),
    bind("window", [], "grave", "workspace", "previous"),
    bind("window", [], "x", "killactive"),
    bind("window", [], "minus", "minimize")
]

private let vimOnlyWindowAdditions: [Bind] = [
    bind("window", [], "g", "layoutmsg", "focusmaster"),
    bind("window", [], "s", "layoutmsg", "orientationnext"),
    bind("window", .maskShift, "s", "layoutmsg", "orientationprev"),
    bind("window", [], "d", "toggledim"),
    bind("window", .maskShift, "d", "toggleblur")
]

@Test func defaultConfigHasTheNewBinds() {
    let all = Set(binds(defaultText))
    for expected in globalAdditions + sharedWindowAdditions + vimOnlyWindowAdditions {
        #expect(all.contains(expected), "missing \(expected)")
    }
}

@Test func wasdConfigHasTheNewBindsThatFitItsKeys() {
    let all = Set(binds(wasdText))
    for expected in globalAdditions + sharedWindowAdditions {
        #expect(all.contains(expected), "missing \(expected)")
    }
    #expect(all.contains(bind("window", [], "s", "movefocus", "d")))
    #expect(all.contains(bind("window", [], "d", "movefocus", "r")))
    #expect(all.contains(bind("window", [], "g", "layoutmsg", "swapwithmaster")))
}

@Test(arguments: [defaultText, wasdText])
func noTwoDefaultBindsShareAKeyInOneSubmap(text: String) {
    var seen: [String: Bind] = [:]
    for bind in binds(text) {
        let slot = "\(bind.submap) \(bind.mods) \(bind.key)"
        #expect(seen[slot] == nil, "\(bind) collides with \(String(describing: seen[slot]))")
        seen[slot] = bind
    }
}

@Test(arguments: [defaultText, wasdText])
func defaultBindsLeaveCommandShortcutsToApps(text: String) {
    for bind in binds(text) where bind.mods & CGEventFlags.maskCommand.rawValue != 0 {
        #expect(bind.key == keyCodes["capslock"], "\(bind) replaces a Command shortcut")
    }
}

@Test(arguments: [defaultText, wasdText])
func everyDefaultBindRunsAKnownDispatcher(text: String) {
    for bind in binds(text) {
        let known = WindowActions.named(bind.dispatcher) != nil
            || FocusEffect.all.contains { $0.dispatcher == bind.dispatcher }
        #expect(known, "unknown dispatcher \(bind.dispatcher)")
    }
}
