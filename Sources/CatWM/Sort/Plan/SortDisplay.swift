import AppKit

struct SortDisplay: Identifiable {
    let id: String
    let name: String
    let short: String
    let isLaptop: Bool
    let aspect: CGFloat
    let screen: NSScreen
    let items: [SortItem]
    let fullscreen: [SortItem]
    let workspaces: [SortWorkspace]
    let active: String?
    let taken: Set<String>
    var perDisplay = false
    var tabs: [[CGWindowID]] = []
}
