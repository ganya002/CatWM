import AppKit
import QuartzCore

func axApp(_ pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, axTimeout)
    return app
}
