import AppKit

extension WindowManager {

    static let maxAnimatedMoves = 6

    var focusedScreen: NSScreen? { currentScreen()?.ns }

}
