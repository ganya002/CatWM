import AppKit

struct ScreenShape {
    var topRadius: CGFloat
    var notchHalfWidth: CGFloat
    var notchHeight: CGFloat
    var topInset: CGFloat
    var isFullscreen: Bool

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

    private static func topRadius(_ screen: NSScreen) -> CGFloat {
        var radii = [Double](repeating: 0, count: 4)
        if let f = cornerRadii, let id = screen.displayID,
           radii.withUnsafeMutableBufferPointer({ f(id, $0.baseAddress, $0.baseAddress! + 1, $0.baseAddress! + 2, $0.baseAddress! + 3) }) == 0 {
            return radii.max() ?? 0
        }
        return screen.safeAreaInsets.top > 0 ? 20 : 0
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    var displayUUID: String? {
        displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }.map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }

    var notchSides: (left: NSRect, right: NSRect)? {
        guard let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return nil }
        return (l, r)
    }
}
