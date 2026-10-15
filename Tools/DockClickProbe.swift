// Compile alongside Sources/ouch/DockWindowPull.swift as main.swift.
// No event tap is installed; replayed events are captured rather than posted to the desktop.
import AppKit
let clicks = DockWindowPull()
var actions = 0
var replayed: [CGEventType] = []
clicks.prepare = { _ in { actions += 1 } }
clicks.post = { replayed.append($0.type) }
func event(_ type: CGEventType, x: CGFloat = 100, flags: CGEventFlags = []) -> CGEvent {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: 100), mouseButton: .left)!
    e.flags = flags
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    return e
}
func drain(_ delay: Double = 0.02) { RunLoop.current.run(until: Date().addingTimeInterval(delay)) }
precondition(clicks.handle(.leftMouseDown, event(.leftMouseDown)))
precondition(clicks.handle(.leftMouseUp, event(.leftMouseUp)))
drain()
precondition(actions == 1 && replayed.isEmpty, "Plain click must import exactly once")
precondition(!clicks.handle(.leftMouseDown, event(.leftMouseDown, flags: .maskAlternate)))
precondition(!clicks.handle(.leftMouseUp, event(.leftMouseUp)))
precondition(clicks.handle(.leftMouseDown, event(.leftMouseDown)))
precondition(clicks.handle(.leftMouseDragged, event(.leftMouseDragged, x: 120)))
precondition(!clicks.handle(.leftMouseUp, event(.leftMouseUp, x: 120)))
precondition(replayed == [.leftMouseDown, .leftMouseDragged], "Drag must restore down before drag")
drain()
precondition(actions == 1, "Drag must not import")
replayed = []
precondition(clicks.handle(.leftMouseDown, event(.leftMouseDown)))
drain(0.4)
precondition(replayed == [.leftMouseDown], "Long press must reach Dock")
precondition(!clicks.handle(.leftMouseUp, event(.leftMouseUp)))
precondition(actions == 1)
replayed = []
precondition(clicks.handle(.leftMouseDown, event(.leftMouseDown)))
precondition(clicks.handle(.leftMouseUp, event(.leftMouseUp, x: 120)))
precondition(replayed == [.leftMouseDown, .leftMouseUp], "Release outside icon must preserve the click pair")
replayed = []
precondition(clicks.handle(.leftMouseDown, event(.leftMouseDown)))
precondition(clicks.handle(.leftMouseUp, event(.leftMouseUp, flags: .maskAlternate)))
precondition(replayed == [.leftMouseDown, .leftMouseUp], "A modifier added during the click must reach Dock")
clicks.prepare = { _ in nil }
precondition(!clicks.handle(.leftMouseDown, event(.leftMouseDown)))
precondition(!clicks.handle(.leftMouseUp, event(.leftMouseUp)))
drain()
precondition(actions == 1)
// Dock-area gate: an auto-hidden bottom Dock on a laptop, plus a second display to the right.
let laptop = (frame: CGRect(x: 0, y: 0, width: 1710, height: 1112), visible: CGRect(x: 0, y: 38, width: 1710, height: 1074))
let side = (frame: CGRect(x: 1710, y: 0, width: 2560, height: 1440), visible: CGRect(x: 1710, y: 25, width: 2560, height: 1300))
let bottom = DockArea.bands(screens: [laptop, side], edge: "bottom", depth: 98)
precondition(bottom.contains { $0.contains(CGPoint(x: 855, y: 1111.5)) }, "Bottom edge click must reach the hit test")
precondition(bottom.contains { $0.contains(CGPoint(x: 855, y: 1112)) }, "The last edge point must reach the hit test")
precondition(!bottom.contains { $0.contains(CGPoint(x: 855, y: 600)) }, "Mid-screen click must skip the hit test")
precondition(!bottom.contains { $0.contains(CGPoint(x: 855, y: 1013)) }, "Click above the band must skip the hit test")
precondition(bottom.contains { $0.contains(CGPoint(x: 3000, y: 1330)) }, "A reserved gap wider than depth must win")
precondition(!bottom.contains { $0.contains(CGPoint(x: 3000, y: 1200)) })
let left = DockArea.bands(screens: [laptop], edge: "left", depth: 98)
precondition(left.contains { $0.contains(CGPoint(x: 0, y: 500)) } && !left.contains { $0.contains(CGPoint(x: 855, y: 1111)) })
let right = DockArea.bands(screens: [laptop], edge: "right", depth: 98)
precondition(right.contains { $0.contains(CGPoint(x: 1709.5, y: 500)) } && !right.contains { $0.contains(CGPoint(x: 0, y: 500)) })
print("PASS: plain click imports once; modifiers, dragging, long press, outside release, and unrelated clicks retain Dock behavior; only Dock edge clicks reach the hit test")
