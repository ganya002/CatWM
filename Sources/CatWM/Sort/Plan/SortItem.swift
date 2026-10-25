import AppKit

struct SortItem: Identifiable {
    let id: CGWindowID
    let title: String
    let app: String
    let bundleID: String?
    let icon: NSImage?
    let recency: Int
}
