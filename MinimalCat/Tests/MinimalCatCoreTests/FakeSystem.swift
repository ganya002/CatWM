import CoreGraphics
@testable import MinimalCatCore

@MainActor
final class FakeSystem: WindowSystem {
    var screens: [Display]
    var list: [WindowInfo]
    var focus: WindowID?
    var applied: [[Move]] = []

    init(screens: [Display] = [FakeSystem.laptop], windows: [WindowInfo] = []) {
        self.screens = screens
        list = windows
        focus = windows.first?.id
    }

    nonisolated static let laptop = Display(
        id: DisplayID("laptop"), frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visible: CGRect(x: 0, y: 33, width: 1512, height: 949))
    nonisolated static let monitor = Display(
        id: DisplayID("monitor"), frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
        visible: CGRect(x: 1512, y: -175, width: 2560, height: 1415))
    nonisolated static let ultrawide = Display(
        id: DisplayID("wide"), frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
        visible: CGRect(x: 0, y: 25, width: 3440, height: 1415))

    nonisolated static func window(_ id: UInt32, _ app: String, _ frame: CGRect, title: String = "") -> WindowInfo {
        WindowInfo(id: WindowID(id), pid: Int32(id), app: app, bundleID: "test.\(app)", title: title, frame: frame)
    }

    func displays() -> [Display] { screens }
    func windows() -> [WindowInfo] { list }
    func focusedWindow() -> WindowID? { focus }
    func focus(_ window: WindowID) { focus = window }
    func apply(_ moves: [Move]) {
        applied.append(moves)
        for move in moves {
            if let index = list.firstIndex(where: { $0.id == move.window }) { list[index].frame = move.end }
        }
    }

    func frame(_ id: UInt32) -> CGRect? { list.first { $0.id == WindowID(id) }?.frame }
}
