import AppKit

final class FocusDim {

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
