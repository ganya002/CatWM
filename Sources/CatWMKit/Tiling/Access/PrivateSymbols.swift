import AppKit
import ApplicationServices

package func symbol<T>(_ name: String, in path: String? = nil) -> T? {
    guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, name) else { return nil }
    return unsafeBitCast(address, to: T.self)
}
