import AppKit
import CatWMKit

private typealias BlurConnectionFn = @convention(c) () -> Int32
private typealias BlurRadiusFn = @convention(c) (Int32, UInt32, UInt32) -> Int32

final class FocusDim {
    struct FeatureMenu {
        let key: String
        let title: String
        let isOn: () -> Bool
    }

    struct Feature {
        let effect: FocusEffect
        let run: () -> Void
        var menu: FeatureMenu?
    }

    static let features: [Feature] = [
        Feature(effect: .dim, run: { shared.toggleDim() },
                menu: FeatureMenu(key: "d", title: "Dim other windows", isOn: { shared.dims })),
        Feature(effect: .blur, run: { shared.toggleBlur() },
                menu: FeatureMenu(key: "b", title: "Blur other windows", isOn: { shared.blurs }))
    ]

    static func quickActions() -> [QuickAction] {
        features.compactMap { feature in
            guard let menu = feature.menu else { return nil }
            let dispatcher = feature.effect.pointer.dispatcher
            let args = feature.effect.pointer.args
            return QuickAction(id: "focus.\(feature.effect.pointer.id)", title: menu.title,
                               keys: [menu.key.uppercased()], keyCode: keyCodes[menu.key], isOn: menu.isOn()) {
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
    var notificationObservers: [NSObjectProtocol] = []

    enum Blur {
        private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        private static let conn: BlurConnectionFn? = symbol("SLSMainConnectionID", in: skylight)
        private static let radius: BlurRadiusFn? = symbol("SLSSetWindowBackgroundBlurRadius", in: skylight)

        static func set(_ window: Int, radius amount: Int) -> Bool {
            guard let conn, let radius, window > 0 else { return false }
            return radius(conn(), UInt32(window), UInt32(max(0, amount))) == 0
        }
    }
}
