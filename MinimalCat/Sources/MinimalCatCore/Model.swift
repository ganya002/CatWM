import CoreGraphics
import Foundation

/// All rects use the global top-left coordinate space that Accessibility uses.
public struct WindowID: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }
    public var description: String { "\(raw)" }
}

public struct DisplayID: Hashable, Codable, Comparable, Sendable {
    public let uuid: String
    public init(_ uuid: String) { self.uuid = uuid }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.uuid < rhs.uuid }
}

public struct Display: Equatable, Sendable {
    public let id: DisplayID
    public let frame: CGRect
    public let visible: CGRect
    public init(id: DisplayID, frame: CGRect, visible: CGRect) {
        self.id = id; self.frame = frame; self.visible = visible
    }
    public var isUltrawide: Bool { frame.width / max(frame.height, 1) >= 2.1 }
}

/// The identity of a monitor setup. A layout is remembered for each one.
public struct DisplaySet: Hashable, Codable, Sendable {
    public let ids: [DisplayID]
    public init(_ displays: [Display]) { ids = displays.map(\.id).sorted() }
    public var key: String { ids.map(\.uuid).joined(separator: "+") }
}

public struct WindowInfo: Equatable, Sendable {
    public let id: WindowID
    public let pid: Int32
    public let app: String
    public let bundleID: String?
    public let title: String
    public var frame: CGRect
    public init(id: WindowID, pid: Int32, app: String, bundleID: String?, title: String, frame: CGRect) {
        self.id = id; self.pid = pid; self.app = app; self.bundleID = bundleID; self.title = title; self.frame = frame
    }
    public var name: String { title.isEmpty ? app : title }
}

public enum Place: String, CaseIterable, Codable, Sendable {
    case left, right, top, bottom, big
}

public enum Side: Sendable { case left, right }

public enum Cause: String, Codable, Sendable {
    case key, menu, restore
}
