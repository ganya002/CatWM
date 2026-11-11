import ApplicationServices

package struct AXReference<Object: AnyObject>: @unchecked Sendable { // style-ok: AX's own locking makes this safe
    package let object: Object

    package init(_ object: Object) { self.object = object }
}
