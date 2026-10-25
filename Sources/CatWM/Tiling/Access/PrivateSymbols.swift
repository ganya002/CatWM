import AppKit
import ApplicationServices

func symbol<T>(_ name: String, in path: String? = nil) -> T? {
    guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, name) else { return nil }
    return unsafeBitCast(address, to: T.self)
}

typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

let axGetWindow: GetWindowFn? = symbol(
    "_AXUIElementGetWindow",
    in: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")
