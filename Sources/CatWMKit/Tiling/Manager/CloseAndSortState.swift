import CoreGraphics
import Foundation

extension WindowManager {
    package struct SortSnapshot {
        package var model: WorkspaceModel
        package var labels: [String: String]
        package var focused: CGWindowID?

        package init(model: WorkspaceModel, labels: [String: String], focused: CGWindowID?) {
            self.model = model
            self.labels = labels
            self.focused = focused
        }
    }
}

package struct CloseAndSortState {
    package var sortSnapshot: WindowManager.SortSnapshot?
    package var sortSession = false
    package var quietWorkspaceHUD = false
    package var closingNow: Set<CGWindowID> = []
    package var closingApps: Set<pid_t> = []
    package var lastClose = Date.distantPast
}
