import AppKit
import SwiftUI
import Testing
@testable import ouch

@MainActor
@Suite struct CursorHoverTests {
    @Test func rowUnderPointerFollowsRowsAndTheDivider() {
        let actions = [
            QuickAction(id: "save", title: "Save", symbol: "plus") {},
            QuickAction(id: "one", title: "One", symbol: "rectangle.3.group") {},
            QuickAction(id: "close", title: "Close", symbol: "xmark", destructive: true) {},
        ]
        let row = Theme.rowHeight
        #expect(CursorActionsView.rowID(at: 0, actions: actions) == "save")
        #expect(CursorActionsView.rowID(at: row - 0.1, actions: actions) == "save")
        #expect(CursorActionsView.rowID(at: row, actions: actions) == "one")
        #expect(CursorActionsView.rowID(at: row * 2, actions: actions) == "close")
        #expect(CursorActionsView.rowID(at: row * 2 + 8, actions: actions) == "close")
        #expect(CursorActionsView.rowID(at: CursorActionsView.contentHeight(for: actions) - 0.1, actions: actions) == "close")
        #expect(CursorActionsView.rowID(at: CursorActionsView.contentHeight(for: actions), actions: actions) == nil)
        #expect(CursorActionsView.rowID(at: -1, actions: actions) == nil)
    }

    @Test func anchorMarksTheTopOfTheFirstRow() throws {
        let model = CursorActionsModel()
        model.open = true
        model.actions = [
            QuickAction(id: "save", title: "Save", symbol: "plus") {},
            QuickAction(id: "one", title: "One", symbol: "rectangle.3.group") {},
        ]
        let size = CursorActionsView.menuSize(for: model.actions)
        let host = NSHostingView(rootView: CursorActionsView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: size.width + 80, height: size.height + 80)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { model.open = false }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let anchor = try #require(CursorActions.shared.rowHover)
        let rows = rowFrames(host).sorted { $0.minY < $1.minY }
        try #require(rows.count == 2)
        let mark = anchor.convert(anchor.bounds, to: host)
        #expect(abs(mark.minX - rows[0].minX) < 0.5)
        #expect(abs(mark.minY - rows[0].minY) < 0.5)
        #expect(abs(mark.width - rows[0].width) < 0.5)
        #expect(abs(pointerDistance(from: anchor, to: rows[0], in: host) - Theme.rowHeight / 2) < 1)
        #expect(abs(pointerDistance(from: anchor, to: rows[1], in: host) - Theme.rowHeight * 1.5) < 1)
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
