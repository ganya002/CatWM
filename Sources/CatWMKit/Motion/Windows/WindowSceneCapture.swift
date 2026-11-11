import AppKit
import os

package struct WindowSceneCapture {
    package struct Display {
        package let screen: Screen
        package let background: CGImage
    }
    package let displays: [Display]
    package let images: [CGWindowID: CGImage]
    package let order: [CGWindowID]
    package let excluded: Set<CGWindowID>

    private typealias NewConnection = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias ReleaseConnection = @convention(c) (Int32) -> Int32
    private typealias Capture = @convention(c) (
        Int32, UnsafePointer<CGWindowID>, Int32, UInt32, CGRect
    ) -> Unmanaged<CFArray>?
    private static let newConnection: NewConnection? = symbol("SLSNewConnection")
    private static let releaseConnection: ReleaseConnection? = symbol("SLSReleaseConnection")
    private static let capture: Capture? = symbol("SLSHWCaptureWindowListInRect")
    private typealias ReadFrame = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32
    private static let readFrame: ReadFrame? = symbol("SLSGetScreenRectForWindow")
    private typealias Connection = @convention(c) () -> Int32
    private typealias Integer = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<Int32>) -> Int32
    private static let mainConnection: Connection? = symbol("SLSMainConnectionID")
    private static let windowOwner: Integer? = symbol("SLSGetWindowOwner")
    private static let windowLevel: Integer? = symbol("SLSGetWindowLevel")

    private final class Session {
        package let connection: Int32
        package init?() {
            guard let newConnection, releaseConnection != nil else { return nil }
            var connection: Int32 = 0
            guard newConnection(0, &connection) == 0, connection != 0 else { return nil }
            self.connection = connection
        }
        deinit { _ = releaseConnection?(connection) }
    }
    private static let session = Session()
    private static let orderSession = Session()

    @discardableResult package static func prepare(window requested: CGWindowID? = nil) -> Bool {
        guard CGPreflightScreenCaptureAccess(), let session, let capture else { return false }
        let id: CGWindowID?
        if let requested { id = requested } else {
            guard let windowOwner, let windowLevel, let mainConnection else { return false }
            let ownConnection = mainConnection()
            id = WindowServerList.onScreen()?.first { id in
                var owner: Int32 = 0, level: Int32 = 0
                guard windowOwner(session.connection, id, &owner) == 0, owner != ownConnection,
                      windowLevel(session.connection, id, &level) == 0, level == 0,
                      let frame = currentFrame(id) else { return false }
                return frame.width >= 64 && frame.height >= 64
            }
        }
        guard var window = id, let frame = currentFrame(window), frame.width >= 64, frame.height >= 64 else {
            return false
        }
        let region = CGRect(x: frame.midX - 32, y: frame.midY - 32, width: 64, height: 64)
        let result = capture(session.connection, &window, 1, 0, region)?.takeRetainedValue() as? [CGImage]
        return result?.first.map { $0.width > 0 && $0.height > 0 } ?? false
    }

    package static func take(
        frames: [CGWindowID: CGRect], screens: [Screen], excluding excluded: Set<CGWindowID> = [],
        includeWindowImages: Bool = true
    ) -> WindowSceneCapture? {
        guard !frames.isEmpty, CGPreflightScreenCaptureAccess(), let session, let capture, let readFrame,
              let ids = WindowServerList.onScreen(), frames.keys.allSatisfy(ids.contains),
              canCapture(Array(frames.values), on: screens),
              unobscured(Array(frames.values), participants: Set(frames.keys), excluding: excluded, order: ids,
                         frame: occludingFrame) else { return nil }
        func unchanged() -> Bool {
            frames.allSatisfy { id, expected in
                var actual = CGRect.null
                return readFrame(session.connection, id, &actual) == 0 && actual.approxEqual(expected, tolerance: 1)
            }
        }
        guard unchanged() else { return nil }
        let ordered = ids.filter { frames[$0] != nil }
        let sources = Array(frames.values)
        func image(_ ids: [CGWindowID], in rect: CGRect) -> CGImage? {
            guard !ids.isEmpty else { return nil }
            let result = ids.withUnsafeBufferPointer { buffer -> Unmanaged<CFArray>? in
                guard let base = buffer.baseAddress else { return nil }
                return capture(session.connection, base, Int32(buffer.count), 0, rect)
            }?.takeRetainedValue() as? [CGImage]
            return result?.first
        }
        var displays: [Display] = []
        var images: [CGWindowID: CGImage] = [:]
        for screen in screens where sources.contains(where: { $0.intersects(screen.frame) }) {
            let region = sources.filter { $0.intersects(screen.frame) }.reduce(CGRect.null) { $0.union($1) }
            let results = OSAllocatedUnfairLock(initialState: [Int: CGImage]())
            let backgroundIDs = ids.filter { frames[$0] == nil && !excluded.contains($0) }
            DispatchQueue.concurrentPerform(iterations: includeWindowImages ? 2 : 1) { index in
                let foreground = includeWindowImages && index == 0
                if let captured = image(foreground ? ordered : backgroundIDs, in: foreground ? region : screen.frame) {
                    results.withLock { $0[foreground ? 0 : 1] = captured }
                }
            }
            guard let background = results.withLock({ $0[1] }) else { return nil }
            if includeWindowImages, let foreground = results.withLock({ $0[0] }) {
                let scaleX = CGFloat(foreground.width) / region.width
                let scaleY = CGFloat(foreground.height) / region.height
                for (id, frame) in frames where frame.intersects(screen.frame) {
                    let local = frame.offsetBy(dx: -region.minX, dy: -region.minY)
                    let pixels = CGRect(x: local.minX * scaleX, y: local.minY * scaleY,
                                        width: local.width * scaleX, height: local.height * scaleY)
                    guard let cropped = foreground.cropping(to: pixels) else { return nil }
                    images[id] = cropped
                }
            }
            displays.append(Display(screen: screen, background: background))
        }
        guard !includeWindowImages || images.count == frames.count, !displays.isEmpty, unchanged() else { return nil }
        return WindowSceneCapture(displays: displays, images: images, order: ordered.reversed(), excluded: excluded)
    }
    package static func windowImage(_ id: CGWindowID) -> (image: CGImage, frame: CGRect)? {
        guard CGPreflightScreenCaptureAccess(), let session, let capture,
              let frame = currentFrame(id), !frame.isEmpty else { return nil }
        var window = id
        let images = capture(session.connection, &window, 1, 0, frame)?.takeRetainedValue() as? [CGImage]
        guard let image = images?.first, let after = currentFrame(id), after.approxEqual(frame, tolerance: 1) else {
            return nil
        }
        return (image, frame)
    }

    package static func currentFrame(_ id: CGWindowID) -> CGRect? {
        guard let session, let readFrame else { return nil }
        var frame = CGRect.null
        guard readFrame(session.connection, id, &frame) == 0, !frame.isNull else { return nil }
        return frame
    }

    package static func windowOrder() -> [CGWindowID]? {
        guard let orderSession else { return nil }
        return WindowServerList.onScreen(connection: orderSession.connection)
    }

    package static func canPresent(
        _ regions: [CGRect], participants: Set<CGWindowID>, excluding excluded: Set<CGWindowID> = [],
        order requested: [CGWindowID]? = nil
    ) -> Bool {
        guard let order = requested ?? windowOrder() else { return false }
        return unobscured(regions, participants: participants, excluding: excluded, order: order, frame: occludingFrame)
    }

    private static func occludingFrame(_ id: CGWindowID) -> CGRect? {
        guard let session, let windowLevel else { return nil }
        var level: Int32 = 0
        guard windowLevel(session.connection, id, &level) == 0 else { return nil }
        return level == 0 ? currentFrame(id) : .zero
    }

    package static func unobscured(_ regions: [CGRect], participants: Set<CGWindowID>,
                                   excluding excluded: Set<CGWindowID> = [], order: [CGWindowID],
                                   frame: (CGWindowID) -> CGRect?) -> Bool {
        var remaining = participants
        guard !remaining.isEmpty else { return false }
        for id in order where !excluded.contains(id) {
            if remaining.remove(id) != nil {
                if remaining.isEmpty { return true }
            } else if !participants.contains(id) {
                guard let other = frame(id) else { return false }
                if regions.contains(where: { $0.intersection(other).width > 1
                    && $0.intersection(other).height > 1 }) { return false }
            }
        }
        return false
    }

    package static func canCapture(_ sources: [CGRect], on screens: [Screen]) -> Bool {
        guard !sources.isEmpty else { return false }
        for (index, frame) in sources.enumerated() {
            guard !frame.isNull, !frame.isEmpty, screens.contains(where: { $0.frame.contains(frame) }),
                  !sources.dropFirst(index + 1).contains(where: { $0.intersection(frame).width > 1
                      && $0.intersection(frame).height > 1 }) else { return false }
        }
        return true
    }
}
