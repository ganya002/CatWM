import CoreGraphics

struct SwitcherItem: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    var workspace = ""
    var elsewhere = false
}
