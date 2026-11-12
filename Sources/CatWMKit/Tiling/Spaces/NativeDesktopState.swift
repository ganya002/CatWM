import CoreGraphics
import Foundation

package struct NativeDesktopState {
    package struct PendingSpace {
        package let display: String
        package let index: Int
        package let until: Date
    }

    package struct SwitchTarget {
        package let workspace: String
        package let until: Date
    }

    package var switchTarget: SwitchTarget?
    package var nativeCatalog = NativeWorkspaceCatalog()
    package var lastNativeCatalogSaved: [String: UInt64] = [:]
    package var lastNativeCatalogHomes: [String: String] = [:]
    package var lastNativeCatalogUUIDs: [String: String] = [:]
    package var nativeGestureSign: Double?
    package var nativeMigration: [CGWindowID: String] = [:]
    package var nativeCreationBusy = false
    package var desktopRemovalScheduled = false
    package var desktopRemovalFailures: [UInt64: Date] = [:]
    package var nativeWorkspaceGeneration = 0
    package var nativeSortNames: Set<String> = []
    package var nativeDroppedWorkspaces: Set<String> = []
    package var homeSpace: [String: UInt64] = [:]
    package var pendingSpace: PendingSpace?
    package var spaceGeneration = 0
    package var movingToSpace = false
}
