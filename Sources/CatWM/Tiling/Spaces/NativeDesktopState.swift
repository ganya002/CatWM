import CoreGraphics
import Foundation

struct NativeDesktopState {
    struct FollowMove {
        let window: Window
        let workspace: String
        let space: UInt64
        let from: String?
    }

    struct PendingSpace {
        let display: String
        let index: Int
        let until: Date
    }

    var nativeCatalog = NativeWorkspaceCatalog()
    var lastNativeCatalogSaved: [String: UInt64] = [:]
    var lastNativeCatalogHomes: [String: String] = [:]
    var lastNativeCatalogUUIDs: [String: String] = [:]
    var nativeGestureSign: Double?
    var nativeMigration: [CGWindowID: String] = [:]
    var nativeCreationBusy = false
    var desktopRemovalScheduled = false
    var desktopRemovalFailures: [UInt64: Date] = [:]
    var nativeWorkspaceGeneration = 0
    var nativeSortNames: Set<String> = []
    var nativeDroppedWorkspaces: Set<String> = []
    var nativeMoveTargets: [CGWindowID: String] = [:]
    var nativeMembership: [CGWindowID: UInt64] = [:]
    var followMoves: [CGWindowID: FollowMove] = [:]
    var homeSpace: [String: UInt64] = [:]
    var pendingSpace: PendingSpace?
    var spaceGeneration = 0
    var movingToSpace = false
}
