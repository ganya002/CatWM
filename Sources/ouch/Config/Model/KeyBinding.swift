import AppKit

struct KeyBinding {
    let keyCode: UInt16
    let mods: CGEventFlags
    let dispatcher: String
    let arg: String
    var submap = ""
    var repeats = false
}
