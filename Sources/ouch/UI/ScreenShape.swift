// UI: a display's shape (rounded top corners, camera notch, fullscreen app) and its IDs.
import AppKit

/// What a screen-edge effect has to follow on one display.
struct ScreenShape {
    /// Radius of the screen's top corners, in points; 0 on square screens and over a fullscreen app.
    var topRadius: CGFloat
    /// Half the width of the camera notch, or 0 on screens without one. Drawn borders start at its edges.
    var notchHalfWidth: CGFloat
    /// Height of the camera notch, or 0 on screens without one.
    var notchHeight: CGFloat
    /// Space at the top the effect leaves out: the black menu bar band over a fullscreen app.
    var topInset: CGFloat
    /// The display shows a fullscreen app's space instead of a desktop.
    var isFullscreen: Bool

    /// A fullscreen app's window is square and, on a notched screen, sits below a black menu bar band.
    /// There the border goes round the window instead of the screen and the notch.
    static func of(_ screen: NSScreen) -> ScreenShape {
        if let uuid = screen.displayUUID, Spaces.isFullscreen(display: uuid) {
            return ScreenShape(topRadius: 0, notchHalfWidth: 0, notchHeight: 0, topInset: screen.safeAreaInsets.top, isFullscreen: true)
        }
        return ScreenShape(topRadius: topRadius(screen), notchHalfWidth: notchHalfWidth(screen), notchHeight: notchHeight(screen),
                           topInset: 0, isFullscreen: false)
    }

    private static func notchHalfWidth(_ screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0, let (l, r) = screen.notchSides else { return 0 }
        return max(0, (r.minX - l.maxX) / 2)
    }

    private static func notchHeight(_ screen: NSScreen) -> CGFloat {
        notchHalfWidth(screen) > 0 ? (screen.auxiliaryTopLeftArea?.height ?? screen.safeAreaInsets.top) : 0
    }

    private typealias CornerRadiiFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>?, UnsafeMutablePointer<Double>?,
                                                      UnsafeMutablePointer<Double>?, UnsafeMutablePointer<Double>?) -> Int32
    private static let cornerRadii: CornerRadiiFn? = symbol("SLSDisplayGetCornerRadii",
                                                            in: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")

    /// How round the screen's top corners are, in points, so the border follows them instead of being
    /// cut off. Built-in MacBook displays round only the top (about 20pt on notched ones); the bottom and
    /// external displays are square. WindowServer knows the exact value per display; the notch is the
    /// fallback guess.
    private static func topRadius(_ screen: NSScreen) -> CGFloat {
        var radii = [Double](repeating: 0, count: 4) // the bottom two, then the top two
        if let f = cornerRadii, let id = screen.displayID,
           radii.withUnsafeMutableBufferPointer({ f(id, $0.baseAddress, $0.baseAddress! + 1, $0.baseAddress! + 2, $0.baseAddress! + 3) }) == 0 {
            return radii.max() ?? 0
        }
        return screen.safeAreaInsets.top > 0 ? 20 : 0
    }
}

extension NSScreen {
    /// The CoreGraphics display this screen shows.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// The display's UUID string, as Spaces and the workspace store key displays.
    var displayUUID: String? {
        displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }.map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }

    /// The menu bar areas left and right of the camera notch; nil on screens without one.
    var notchSides: (left: NSRect, right: NSRect)? {
        guard let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return nil }
        return (l, r)
    }
}
