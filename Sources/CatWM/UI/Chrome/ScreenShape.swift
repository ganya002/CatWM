import AppKit
import CatWMKit

struct ScreenShape: Equatable {
    var topRadius: CGFloat
    var notchHalfWidth: CGFloat
    var notchHeight: CGFloat
    var topInset: CGFloat
    var isFullscreen: Bool

    static func of(_ screen: NSScreen) -> ScreenShape {
        if let uuid = screen.displayUUID, Spaces.isFullscreen(display: uuid) {
            return ScreenShape(topRadius: 0, notchHalfWidth: 0, notchHeight: 0, topInset: screen.safeAreaInsets.top,
                               isFullscreen: true)
        }
        return ScreenShape(topRadius: topRadius(screen), notchHalfWidth: notchHalfWidth(screen),
                           notchHeight: notchHeight(screen), topInset: 0, isFullscreen: false)
    }

    private static func notchHalfWidth(_ screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0, let (left, right) = screen.notchSides else { return 0 }
        return max(0, (right.minX - left.maxX) / 2)
    }

    private static func notchHeight(_ screen: NSScreen) -> CGFloat {
        notchHalfWidth(screen) > 0 ? (screen.auxiliaryTopLeftArea?.height ?? screen.safeAreaInsets.top) : 0
    }

    private typealias RadiusPointer = UnsafeMutablePointer<Double>?
    private typealias CornerRadiiFn = @convention(c) (CGDirectDisplayID, RadiusPointer, RadiusPointer,
                                                      RadiusPointer, RadiusPointer) -> Int32
    private static let cornerRadii: CornerRadiiFn? = symbol(
        "SLSDisplayGetCornerRadii", in: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")

    private static func topRadius(_ screen: NSScreen) -> CGFloat {
        var radii = [Double](repeating: 0, count: 4)
        if let cornerRadii, let id = screen.displayID,
           radii.withUnsafeMutableBufferPointer({ buffer in
               guard let base = buffer.baseAddress else { return -1 }
               return cornerRadii(id, base, base + 1, base + 2, base + 3)
           }) == 0 {
            return radii.max() ?? 0
        }
        return screen.safeAreaInsets.top > 0 ? 20 : 0
    }
}

extension NSScreen {
    var notchSides: (left: NSRect, right: NSRect)? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return (left, right)
    }
}
