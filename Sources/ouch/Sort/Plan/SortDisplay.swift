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

    var isSorted: Bool { workspaces.filter { !$0.ids.isEmpty }.count > 1 }
}
