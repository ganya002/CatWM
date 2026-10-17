import AppKit

extension WindowManager {

    struct SortSnapshot {
        var model: WorkspaceModel
        var labels: [String: String]
        var focused: CGWindowID?
    }

}
