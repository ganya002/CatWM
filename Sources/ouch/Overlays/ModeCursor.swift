// Overlays: keeps the plain arrow pointer while a mode (submap) is on.
import AppKit

/// While a mode is on, the pointer is always the arrow, so an I-beam, a resize arrow or a link hand from
/// the app below doesn't suggest that the mouse acts on the app. Clicks still go through to the apps, so
/// no panel can own the pointer: ouch sets the arrow from the background (`SetsCursorInBackground` on
/// its WindowServer connection) and sets it again at 120 Hz, since the app below sets its own shape on
/// each mouse move. When the mode ends, a synthetic move lets that app set its shape again.
final class ModeCursor {
    static let shared = ModeCursor()

    private typealias Connection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private let setInBackground: ((Bool) -> Void)?
    private var timer: Timer?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func lookup<T>(_ name: String, as: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        guard let connection = lookup("SLSMainConnectionID", as: Connection.self),
              let set = lookup("SLSSetConnectionProperty", as: SetProperty.self) else {
            setInBackground = nil
            return
        }
        let cid = connection()
        setInBackground = { on in
            _ = set(cid, cid, "SetsCursorInBackground" as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse)!)
        }
    }

    func setActive(_ on: Bool) {
        guard on != (timer != nil) else { return }
        if on {
            setInBackground?(true)
            NSCursor.arrow.set()
            let t = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in NSCursor.arrow.set() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate()
            timer = nil
            setInBackground?(false)
            CursorRefresh.soon(after: 0)
        }
    }
}
