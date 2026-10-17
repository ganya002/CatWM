import AppKit

final class FocusDim {

    struct Feature {
        let options: [ConfigOption]
        let pointer: CursorShortcutSpec
        let run: () -> Void
        var dispatcherBefore = "retile"
        var menu: Menu? = nil

        struct Menu {
            let key: String
            let title: String
            let on: () -> Bool
        }
    }

    static let features: [Feature] = [
        Feature(options: [
            .bool("dim-other-windows", \.dimOtherWindows)
                .documented("bool", "darken every window but the focused one").aliases("dim_inactive")
                .section("focused window")
                .note("Make the focused window stand out: darken the others (strength 0-1) and/or blur them (radius in points).")
                .setting(.windows, "windows.dimOthers", "Dim other windows", help: "Darkens everything but the focused window",
                         keywords: "focus darken inactive spotlight hazeover", order: 3),
            .points("dim-strength", \.dimStrength, valid: 0...1, convert: { $0 > 1 ? $0 / 100 : $0 })
                .documented("0–1 (or 0–100)", "how dark; a value above 1 is read as percent")
                .setting(.windows, "windows.dimStrength", "Dim strength", help: "How dark the other windows get",
                         keywords: "darken amount opacity", range: 0...100, scale: 100, order: 4, enabled: { $0.dimOtherWindows }, unit: "%")
        ], pointer: CursorShortcutSpec(id: "dim", action: Action(title: "Toggle Dim Other Windows", category: .app, dispatcher: "toggledim", args: "", symbol: "circle.lefthalf.filled"),
                                          title: "Dim Other Windows", actionBefore: "reload ", hint: "Dim",
                                          selected: { _ in shared.dims }), run: { shared.toggleDim() },
                menu: Feature.Menu(key: "d", title: "Dim other windows", on: { shared.dims })),
        Feature(options: [
            .bool("blur-other-windows", \.blurOtherWindows)
                .documented("bool", "blur every window but the focused one; combines with dimming")
                .setting(.windows, "windows.blurOthers", "Blur other windows", help: "Softens everything but the focused window",
                         keywords: "focus soft inactive spotlight", order: 5),
            .points("blur-radius", \.blurRadius, valid: 1...100, convert: { $0.rounded() })
                .documented("1–100 (points)", "rounded to whole points. The Settings slider shows 2–60")
                .setting(.windows, "windows.blurRadius", "Blur radius", help: "How soft the other windows look", keywords: "soft amount points", range: 2...60, order: 6, enabled: { $0.blurOtherWindows })
        ], pointer: CursorShortcutSpec(id: "blur", action: Action(title: "Toggle Blur Other Windows", category: .app, dispatcher: "toggleblur", args: "", symbol: "drop.halffull"),
                                          title: "Blur Other Windows", actionBefore: "reload ", hint: "Blur",
                                          selected: { _ in shared.blurs }), run: { shared.toggleBlur() },
                menu: Feature.Menu(key: "b", title: "Blur other windows", on: { shared.blurs })),
    ]

    static func quickActions() -> [QuickAction] {
        features.compactMap { feature in
            guard let menu = feature.menu else { return nil }
            let dispatcher = feature.pointer.dispatcher
            let args = feature.pointer.args
            return QuickAction(id: "focus.\(feature.pointer.id)", title: menu.title, symbol: feature.pointer.action.symbol,
                               keys: [menu.key.uppercased()], keyCode: keyCodes[menu.key], isOn: menu.on()) {
                WindowManager.shared.dispatch(dispatcher, args)
            }
        }
    }

    static let shared = FocusDim()

    var dims = false
    var blurs = false
    var strength: CGFloat = 0.3
    var radius = 20
    var enabled: Bool { dims || blurs }

    struct Pair { var front: NSPanel; var spare: NSPanel }
    var pairs: [CGDirectDisplayID: Pair] = [:]
    var panelNumbers = Set<Int>()
    var target: CGWindowID?
    var generation = 0
    var pending = false
    var observing = false
    let fade = 0.2
    var configured: (dim: Bool, blur: Bool)?

    enum Blur {
        private typealias ConnFn = @convention(c) () -> Int32
        private typealias RadiusFn = @convention(c) (Int32, UInt32, UInt32) -> Int32
        private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        private static let conn: ConnFn? = symbol("SLSMainConnectionID", in: skylight)
        private static let radius: RadiusFn? = symbol("SLSSetWindowBackgroundBlurRadius", in: skylight)

        static func set(_ window: Int, radius r: Int) -> Bool {
            guard let conn, let radius, window > 0 else { return false }
            return radius(conn(), UInt32(window), UInt32(max(0, r))) == 0
        }
    }
}
