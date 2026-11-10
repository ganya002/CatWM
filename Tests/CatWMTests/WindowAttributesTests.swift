import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WindowAttributesTests {
    private func values() throws -> [Any] {
        var position = CGPoint(x: -1200, y: 38), size = CGSize(width: 800, height: 600)
        return [true, false, kAXStandardWindowSubrole,
                try #require(AXValueCreate(.cgPoint, &position)), try #require(AXValueCreate(.cgSize, &size)), "Window"]
    }

    @Test func aBatchKeepsEachAttributeInItsOriginalPosition() throws {
        let read = try #require(WindowAttributes.decode(values()))
        #expect(read.fullscreen && !read.minimized)
        #expect(read.subrole == kAXStandardWindowSubrole)
        #expect(read.title == "Window")
        #expect(read.frame == CGRect(x: -1200, y: 38, width: 800, height: 600))
    }

    @Test func missingAttributesDoNotShiftLaterAttributes() throws {
        var attributes = try values()
        attributes[0] = NSNull()
        attributes[2] = NSNull()
        attributes[5] = NSNull()
        let read = try #require(WindowAttributes.decode(attributes))
        #expect(!read.fullscreen && !read.minimized)
        #expect(read.subrole == nil && read.title == nil)
        #expect(!read.frame.isNull)
        attributes[3] = NSNull()
        #expect(WindowAttributes.decode(attributes)?.frame.isNull == true)
    }

    @Test func perAttributeErrorsAreNotBooleanFlagsOrGeometry() throws {
        var error = AXError.attributeUnsupported
        let value = try #require(AXValueCreate(.axError, &error))
        let read = try #require(WindowAttributes.decode(Array(repeating: value, count: 6)))
        #expect(!read.fullscreen && !read.minimized)
        #expect(read.subrole == nil && read.title == nil)
        #expect(read.frame.isNull)
    }

    @Test func invalidGeometryCannotReachTheLayout() throws {
        var attributes = try values()
        attributes.swapAt(3, 4)
        #expect(WindowAttributes.decode(attributes)?.frame.isNull == true)
        var position = CGPoint(x: Double.infinity, y: 0)
        attributes[3] = try #require(AXValueCreate(.cgPoint, &position))
        #expect(WindowAttributes.decode(attributes)?.frame.isNull == true)
        #expect(WindowAttributes.decode([]) == nil)
        #expect(WindowAttributes.decode(Array(attributes.dropLast())) == nil)
    }
}
