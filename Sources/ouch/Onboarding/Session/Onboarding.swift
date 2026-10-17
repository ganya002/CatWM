import AppKit
import SwiftUI

final class Onboarding {

    static let shared = Onboarding()
    static let doneKey = "didOnboard"

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    weak var statusButton: NSStatusBarButton? {
        didSet { MenuBarTip.shared.statusButton = statusButton }
    }
    var intro: Intro?
    var welcome: OuchPanel?
    let welcomeModel = WelcomeModel()
    var poll: Timer?
    var coach: Coach?
    var openedLoginItems = false
    var offering = false
    var firstRun = false

    var isRunning: Bool { intro != nil || welcome != nil || coach != nil || offering }

}
