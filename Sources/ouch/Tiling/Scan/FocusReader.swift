import AppKit

final class FocusReader {
    enum Result { case focused(CGWindowID?), unavailable }

    private let read: (pid_t) -> Result
    private var queues: [pid_t: DispatchQueue] = [:]

    init(read: @escaping (pid_t) -> Result = FocusReader.read) {
        self.read = read
    }

    func observe(_ pid: pid_t, done: @escaping (Result) -> Void) {
        let queue = queues[pid] ?? DispatchQueue(label: "ouch.focus-read.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        queue.async { [read] in
            let id = read(pid)
            DispatchQueue.main.async { done(id) }
        }
    }

    private static func read(_ pid: pid_t) -> Result {
        dispatchPrecondition(condition: .notOnQueue(.main))
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp(pid), kAXFocusedWindowAttribute as CFString, &value)
        if result == .noValue || result == .attributeUnsupported { return .focused(nil) }
        guard result == .success else { return .unavailable }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .focused(nil) }
        return resolve(unsafeDowncast(value, to: AXUIElement.self))
    }

    static func resolve(_ focusedElement: AXUIElement) -> Result {
        var element = focusedElement
        if element.string(kAXRoleAttribute) == kAXSheetRole {
            guard let parent = element.element(kAXParentAttribute) else { return .focused(nil) }
            element = parent
        }
        return .focused(element.windowID)
    }
}
