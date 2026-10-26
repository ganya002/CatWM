import AppKit
import MinimalCatCore

/// The real Mac: windows come from the window server and Accessibility, and moves go through `Animator`.
/// Frames come from Accessibility, because the window server list lags behind a move.
@MainActor
public final class AXSystem: WindowSystem {
    private struct Known { let element: AXUIElement; let pid: pid_t }
    private struct Entry { let id: CGWindowID; let pid: pid_t; let owner: String; let frame: CGRect }

    /// When set, only windows of these processes are seen or moved. The check tool uses it.
    public var scope: Set<pid_t>?
    private var known: [CGWindowID: Known] = [:]
    private let animator = Animator()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    public init(scope: Set<pid_t>? = nil) { self.scope = scope }

    public func displays() -> [Display] { Displays.current() }

    public func windows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let entries = list.compactMap { info -> Entry? in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  scope?.contains(pid) ?? true,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 40, frame.height > 40 else { return nil }
            return Entry(id: number, pid: pid, owner: info[kCGWindowOwnerName as String] as? String ?? "", frame: frame)
        }
        for pid in Set(entries.map(\.pid)) where entries.contains(where: { $0.pid == pid && known[$0.id] == nil }) {
            learn(pid)
        }
        return entries.compactMap { entry in
            let (id, pid, owner, frame) = (entry.id, entry.pid, entry.owner, entry.frame)
            guard let element = known[id]?.element,
                  element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole as String,
                  !element.flag(kAXMinimizedAttribute) else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            return WindowInfo(id: WindowID(id), pid: pid, app: app?.localizedName ?? owner,
                              bundleID: app?.bundleIdentifier, title: element.string(kAXTitleAttribute) ?? "",
                              frame: animator.heading[id] ?? element.frame ?? frame)
        }
    }

    public func focusedWindow() -> WindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, scope?.contains(pid) ?? true,
              let id = AXUIElement.app(pid).element(kAXFocusedWindowAttribute)?.windowID else { return nil }
        return WindowID(id)
    }

    public func apply(_ moves: [Move]) {
        animator.move(moves.compactMap { move in
            guard let window = known[move.window.raw] else { return nil }
            return Animator.Target(element: window.element, id: move.window.raw, pid: window.pid,
                                   start: move.start, end: move.end)
        })
    }

    public func focus(_ window: WindowID) {
        guard let known = known[window.raw] else { return }
        WindowFocus.focus(known.element, id: window.raw, pid: known.pid)
    }

    /// The frame Accessibility reports now. The check tool reads it back after a move.
    public func frame(of window: WindowID) -> CGRect? { known[window.raw]?.element.frame }

    private func learn(_ pid: pid_t) {
        known = known.filter { $0.value.pid != pid }
        for element in AXUIElement.app(pid).elements(kAXWindowsAttribute) {
            guard let id = element.windowID else { continue }
            AXUIElementSetMessagingTimeout(element, 0.25)
            known[id] = Known(element: element, pid: pid)
        }
    }
}
