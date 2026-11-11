import AppKit
import ApplicationServices
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

package enum AgentWindowIO {
    private static let textRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXSearchField"]
    private static let keyCodes: [String: CGKeyCode] = {
        let rows: [(String, [CGKeyCode])] = [
            ("asdfhgzxcvbqweryt", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17]),
            ("123465=97-80]ou[ip", [18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35]),
            ("lj'k;\\,/nm.", [37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47])
        ]
        var table: [String: CGKeyCode] = [
            "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
            "left": 123, "right": 124, "down": 125, "up": 126
        ]
        for (letters, codes) in rows { for (letter, code) in zip(letters, codes) { table[String(letter)] = code } }
        return table
    }()
    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "shift": .maskShift, "option": .maskAlternate, "ctrl": .maskControl
    ]

    package static func window(_ id: CGWindowID, pid: pid_t) -> AXUIElement? {
        axApp(pid).elements(kAXWindowsAttribute).first { $0.windowID == id }
    }

    package static func title(of window: AXUIElement) -> String? { window.string(kAXTitleAttribute) }

    private static func find(in window: AXUIElement, _ matches: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [window]
        var visited = 0
        while visited < 500, !queue.isEmpty {
            let element = queue.removeFirst()
            visited += 1
            if matches(element) { return element }
            queue += element.elements(kAXChildrenAttribute)
        }
        return nil
    }

    private static func textField(in window: AXUIElement, pid: pid_t) -> AXUIElement? {
        func isText(_ element: AXUIElement) -> Bool { textRoles.contains(element.string(kAXRoleAttribute) ?? "") }
        if let focused = axApp(pid).element(kAXFocusedUIElementAttribute), isText(focused),
           focused.element(kAXWindowAttribute)?.windowID == window.windowID { return focused }
        return find(in: window, isText)
    }

    package static func press(button title: String, in window: AXUIElement) -> Bool {
        let wanted = title.lowercased()
        let button = find(in: window) { element in
            element.string(kAXRoleAttribute) == kAXButtonRole
                && [kAXTitleAttribute, kAXDescriptionAttribute].contains { element.string($0)?.lowercased() == wanted }
        }
        guard let button else { return false }
        return button.noted { AXUIElementPerformAction(button, kAXPressAction as CFString) } == .success
    }

    package static func text(in window: AXUIElement, pid: pid_t) -> String? {
        textField(in: window, pid: pid)?.string(kAXValueAttribute)
    }

    package static func type(_ text: String, in window: AXUIElement, pid: pid_t) -> String {
        if let field = textField(in: window, pid: pid), field.isSettable(kAXValueAttribute),
           field.set(kAXValueAttribute, ((field.string(kAXValueAttribute) ?? "") + text) as CFString) {
            return "ax"
        }
        let source = CGEventSource(stateID: .privateState)
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.flags = []
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event?.postToPid(pid)
            }
        }
        return "events"
    }

    package static func press(_ keys: String, pid: pid_t) throws {
        let parts = keys.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        var flags = CGEventFlags()
        for name in parts.dropLast() {
            guard let flag = modifiers[name] else { throw ControlError.invalid("Unknown modifier `\(name)`") }
            flags.insert(flag)
        }
        guard let name = parts.last, let code = keyCodes[name] else {
            throw ControlError.invalid("Unknown key `\(parts.last ?? "")`")
        }
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.postToPid(pid)
        }
    }

    package static func capture(_ id: CGWindowID, to url: URL) async throws {
        func failure(_ message: String) -> ControlError { ControlError(code: "capture_failed", message: message) }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let target = content.windows.first(where: { $0.windowID == id }) else {
                throw failure("ScreenCaptureKit does not list window \(id)")
            }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { throw failure("Cannot write \(url.path)") }
            CGImageDestinationAddImage(file, image, nil)
            guard CGImageDestinationFinalize(file) else { throw failure("Cannot write \(url.path)") }
        } catch let error as ControlError {
            throw error
        } catch {
            throw failure(error.localizedDescription)
        }
    }
}
