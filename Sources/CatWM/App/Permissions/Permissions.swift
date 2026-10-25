import AppKit
import SwiftUI

enum Permissions {
    static func request() { Permission.accessibility.request() }
    static func reset() { Permission.accessibility.reset() }
    static func requestInputMonitoring() { Permission.inputMonitoring.request() }
}
