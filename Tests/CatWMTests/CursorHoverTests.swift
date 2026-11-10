import AppKit
@testable import CatWM
@testable import CatWMKit
import SwiftUI
import Testing

@MainActor
@Suite struct CursorHoverTests {
    @Test func rowUnderPointerFollowsRowsAndTheDivider() {
        let actions = [
            QuickAction(id: "save", title: "Save") {},
            QuickAction(id: "one", title: "One") {},
            QuickAction(id: "close", title: "Close", destructive: true) {}
        ]
        let row = Theme.rowHeight
        #expect(CursorActionsView.rowID(at: 0, actions: actions) == "save")
        #expect(CursorActionsView.rowID(at: row - 0.1, actions: actions) == "save")
        #expect(CursorActionsView.rowID(at: row, actions: actions) == "one")
        #expect(CursorActionsView.rowID(at: row * 2, actions: actions) == "close")
        #expect(CursorActionsView.rowID(at: row * 2 + 8, actions: actions) == "close")
        #expect(CursorActionsView.rowID(
            at: CursorActionsView.contentHeight(for: actions) - 0.1, actions: actions
        ) == "close")
        #expect(CursorActionsView.rowID(at: CursorActionsView.contentHeight(for: actions), actions: actions) == nil)
        #expect(CursorActionsView.rowID(at: -1, actions: actions) == nil)
    }

    @Test func pointerMissesRowsHiddenOutsideTheViewport() {
        let actions = (0..<12).map { QuickAction(id: "\($0)", title: "\($0)") {} }
        let row = Theme.rowHeight
        let visible = 0..<(9 * row)
        #expect(CursorActionsView.rowUnderPointer(
            x: 10, y: row / 2, width: 200, actions: actions, visible: visible
        ) == "0")
        #expect(CursorActionsView.rowUnderPointer(
            x: 10, y: 9.5 * row, width: 200, actions: actions, visible: visible
        ) == nil)
        let scrolled = (3 * row)..<(12 * row)
        #expect(CursorActionsView.rowUnderPointer(
            x: 10, y: row / 2, width: 200, actions: actions, visible: scrolled
        ) == nil)
        #expect(CursorActionsView.rowUnderPointer(
            x: 10, y: 3.5 * row, width: 200, actions: actions, visible: scrolled
        ) == "3")
    }

    @Test func anchorMarksTheTopOfTheFirstRow() throws {
        let model = CursorActionsModel()
        model.open = true
        model.actions = [
            QuickAction(id: "save", title: "Save") {},
            QuickAction(id: "one", title: "One") {}
        ]
        let size = CursorActionsView.menuSize(for: model.actions)
        let host = NSHostingView(rootView: CursorActionsView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: size.width + 80, height: size.height + 80)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { model.open = false }
        host.layoutSubtreeIfNeeded()
        let anchor = try #require(anchor(in: host) { rowFrames(host).count == 2 })
        let rows = rowFrames(host).sorted { $0.minY < $1.minY }
        try #require(rows.count == 2)
        let mark = anchor.convert(anchor.bounds, to: host)
        #expect(abs(mark.minX - rows[0].minX) < 0.5)
        #expect(abs(mark.minY - rows[0].minY) < 0.5)
        #expect(abs(mark.width - rows[0].width) < 0.5)
        #expect(abs(pointerDistance(from: anchor, to: rows[0], in: host) - Theme.rowHeight / 2) < 1)
        #expect(abs(pointerDistance(from: anchor, to: rows[1], in: host) - Theme.rowHeight * 1.5) < 1)
        let hit = try hitRow(anchor, in: rows[0], actions: model.actions)
        #expect(hit == "save")
    }

    @Test func pointerBelowTheViewportMissesHiddenRows() throws {
        let model = CursorActionsModel()
        model.open = true
        model.actions = (0..<12).map { QuickAction(id: "\($0)", title: "Row \($0)") {} }
        let size = CursorActionsView.menuSize(for: model.actions)
        let host = NSHostingView(rootView: CursorActionsView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: size.width + 80, height: size.height + 80)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { model.open = false }
        host.layoutSubtreeIfNeeded()
        let anchor = try #require(anchor(in: host) { CursorActions.shared.rowHover?.enclosingScrollView != nil })
        let clip = try #require(anchor.enclosingScrollView?.contentView)
        let below = clip.convert(CGPoint(x: clip.bounds.midX, y: clip.bounds.maxY + 24), to: nil)
        let origin = anchor.convert(CGPoint.zero, to: nil)
        let y = origin.y - below.y
        #expect(y < CursorActionsView.contentHeight(for: model.actions))
        #expect(CursorActions.rowUnder(anchor, at: below, x: below.x - origin.x, y: y, actions: model.actions) == nil)
        let above = clip.convert(CGPoint(x: clip.bounds.midX, y: clip.bounds.minY - 16), to: nil)
        #expect(CursorActions.rowUnder(
            anchor, at: above, x: above.x - origin.x, y: origin.y - above.y, actions: model.actions
        ) == nil)
    }

    private func anchor(in host: NSView, when ready: () -> Bool) -> NSView? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let anchor = CursorActions.shared.rowHover, anchor.isDescendant(of: host), ready() { return anchor }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return nil
    }

    private func hitRow(_ anchor: NSView, in row: NSRect, actions: [QuickAction]) throws -> String? {
        let host = try #require(anchor.window?.contentView)
        let mid = host.convert(CGPoint(x: row.midX, y: row.midY), to: nil)
        let origin = anchor.convert(CGPoint.zero, to: nil)
        return CursorActions.rowUnder(anchor, at: mid, x: mid.x - origin.x, y: origin.y - mid.y, actions: actions)
    }

    private func pointerDistance(from anchor: NSView, to row: NSRect, in host: NSView) -> CGFloat {
        let mid = host.convert(CGPoint(x: row.midX, y: row.midY), to: nil)
        return anchor.convert(CGPoint.zero, to: nil).y - mid.y
    }

    private func rowFrames(_ root: NSView) -> [NSRect] {
        var found: [NSRect] = []
        func walk(_ view: NSView) {
            let frame = view.convert(view.bounds, to: root)
            if abs(frame.height - Theme.rowHeight) < 1, frame.width > 100 { found.append(frame) }
            for child in view.subviews { walk(child) }
        }
        walk(root)
        return found
    }
}
