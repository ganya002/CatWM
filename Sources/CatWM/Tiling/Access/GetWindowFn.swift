import AppKit
import ApplicationServices

typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
