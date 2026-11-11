import ApplicationServices

package protocol AXObject: AnyObject {}

extension AXUIElement: AXObject {}
extension AXObserver: AXObject {}

package struct AXReference<Object: AXObject>: @unchecked Sendable { // style-ok: AX's own locking makes this safe
    package let object: Object

    package init(_ object: Object) { self.object = object }
}
