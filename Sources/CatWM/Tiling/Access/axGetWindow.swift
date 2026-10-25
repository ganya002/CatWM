import AppKit
import ApplicationServices

let axGetWindow: GetWindowFn? = symbol(
    "_AXUIElementGetWindow",
    in: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")
