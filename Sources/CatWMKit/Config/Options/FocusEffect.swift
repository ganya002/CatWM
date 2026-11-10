import Foundation

package struct FocusEffect {
    package let options: [ConfigOption]
    package let pointer: CursorShortcutSpec
    package var dispatcherBefore = "retile"

    package var dispatcher: String { pointer.dispatcher }
    package var title: String { pointer.action.title }

    package static let all = [dim, blur]

    package static let dim = FocusEffect(options: [
        .bool("dim-other-windows", \.dimOtherWindows).script("focusDim.dim")
            .documented("bool", "darken every window but the focused one").aliases("dim_inactive")
            .section("focused window")
            .note(
                "Make the focused window stand out: darken the others (strength 0-1) "
                    + "and/or blur them (radius in points)."
            )
            .setting(.windows, "windows.dimOthers", "Dim other windows",
                     help: "Darkens everything but the focused window",
                     keywords: "focus darken inactive spotlight hazeover", order: 3),
        .points("dim-strength", \.dimStrength, valid: 0...1, convert: { $0 > 1 ? $0 / 100 : $0 })
            .script("focusDim.dimStrength")
            .documented("0–1 (or 0–100)", "how dark; a value above 1 is read as percent")
            .setting(.windows, "windows.dimStrength", "Dim strength", help: "How dark the other windows get",
                     keywords: "darken amount opacity", range: 0...100, scale: 100, order: 4,
                     enabled: { $0.dimOtherWindows }, unit: "%")
    ], pointer: CursorShortcutSpec(id: "dim",
                                   action: Action(title: "Toggle Dim Other Windows", category: .app,
                                                  dispatcher: "toggledim", args: "", symbol: "circle.lefthalf.filled"),
                                   title: "Dim Other Windows", actionBefore: "reload ", hint: "Dim",
                                   selected: { $0.dimmed }))

    package static let blur = FocusEffect(options: [
        .bool("blur-other-windows", \.blurOtherWindows).script("focusDim.blur")
            .documented("bool", "blur every window but the focused one; combines with dimming")
            .setting(.windows, "windows.blurOthers", "Blur other windows",
                     help: "Softens everything but the focused window",
                     keywords: "focus soft inactive spotlight", order: 5),
        .points("blur-radius", \.blurRadius, valid: 1...100, convert: { $0.rounded() })
            .script("focusDim.blurRadius")
            .documented("1–100 (points)", "rounded to whole points. The Settings slider shows 2–60")
            .setting(.windows, "windows.blurRadius", "Blur radius", help: "How soft the other windows look",
                     keywords: "soft amount points", range: 2...60, order: 6,
                     enabled: { $0.blurOtherWindows })
    ], pointer: CursorShortcutSpec(id: "blur",
                                   action: Action(title: "Toggle Blur Other Windows", category: .app,
                                                  dispatcher: "toggleblur", args: "", symbol: "drop.halffull"),
                                   title: "Blur Other Windows", actionBefore: "reload ", hint: "Blur",
                                   selected: { $0.blurred }))
}
