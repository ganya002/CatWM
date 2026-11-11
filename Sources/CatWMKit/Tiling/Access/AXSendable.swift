import ApplicationServices

extension AXUIElement: @retroactive @unchecked Sendable {} // style-ok: immutable CF reference, AX calls are thread-safe
extension AXObserver: @retroactive @unchecked Sendable {} // style-ok: immutable CF reference, AX calls are thread-safe
