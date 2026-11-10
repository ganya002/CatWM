import AppKit
import CatWMKit

final class ModeCursor {
    static let shared = ModeCursor()

    private typealias Connection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private let setInBackground: ((Bool) -> Void)?
    private var timer: Timer?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func lookup<T>(_ name: String, as _: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        guard let connection = lookup("SLSMainConnectionID", as: Connection.self),
              let set = lookup("SLSSetConnectionProperty", as: SetProperty.self) else {
            setInBackground = nil
            return
        }
        let cid = connection()
        setInBackground = { active in
            guard let value = active ? kCFBooleanTrue : kCFBooleanFalse else { return }
            _ = set(cid, cid, "SetsCursorInBackground" as CFString, value)
        }
    }

    private var mode = false
    private var held: NSCursor?

    func setActive(_ active: Bool) {
        mode = active
        apply()
    }

    func hold(_ cursor: NSCursor?) {
        held = cursor
        apply()
    }

    private var cursor: NSCursor? { held ?? (mode ? .arrow : nil) }

    private func apply() {
        guard let cursor else {
            guard timer != nil else { return }
            timer?.invalidate()
            timer = nil
            setInBackground?(false)
            WindowManager.shared.cursorRefresh.soon(after: 0)
            return
        }
        if timer == nil {
            setInBackground?(true)
            let repeating = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.cursor?.set() }
            RunLoop.main.add(repeating, forMode: .common)
            timer = repeating
        }
        cursor.set()
    }
}
