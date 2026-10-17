import AppKit
import SwiftUI

final class WelcomeModel: ObservableObject {
    enum Page { case permissions, keys }
    @Published var page = Page.permissions
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var login = false
    @Published var style: KeyStyle?
    @Published var landed = false
    var allowAccessibility: () -> Void = {}
    var allowInputMonitoring: () -> Void = {}
    var allowLogin: () -> Void = {}
    var skip: () -> Void = {}
    var next: () -> Void = {}
    var start: () -> Void = {}
}
