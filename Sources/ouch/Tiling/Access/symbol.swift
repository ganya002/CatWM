import AppKit
import ApplicationServices

func symbol<T>(_ name: String, in path: String? = nil) -> T? {
    guard let handle = dlopen(path, RTLD_LAZY), let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}
